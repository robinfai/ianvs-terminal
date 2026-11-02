package httpapi

import (
	"bufio"
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/url"
	"strings"
)

// Official OpenAI uses Responses for tool calling. Custom OpenAI-compatible
// endpoints keep their existing Chat Completions contract.
func usesAIResponses(provider, endpoint string) bool {
	u, err := url.Parse(endpoint)
	return err == nil && provider == "openai" && u.Hostname() == "api.openai.com"
}

func aiResponsesPayload(chat map[string]json.RawMessage) (map[string]json.RawMessage, error) {
	var messages []map[string]json.RawMessage
	if err := json.Unmarshal(chat["messages"], &messages); err != nil {
		return nil, err
	}
	input := []any{}
	for _, msg := range messages {
		var role string
		if json.Unmarshal(msg["role"], &role) != nil {
			return nil, errors.New("invalid message role")
		}
		if role == "tool" {
			var id, output string
			if json.Unmarshal(msg["tool_call_id"], &id) != nil || id == "" || json.Unmarshal(msg["content"], &output) != nil {
				return nil, errors.New("invalid tool output")
			}
			input = append(input, map[string]any{"type": "function_call_output", "call_id": id, "output": output})
			continue
		}
		if role != "system" && role != "developer" && role != "user" && role != "assistant" {
			return nil, errors.New("invalid message role")
		}
		content := msg["content"]
		if len(content) > 0 && string(content) != "null" {
			var text string
			if json.Unmarshal(content, &text) != nil {
				var parts []struct {
					Type string `json:"type"`
					Text string `json:"text"`
				}
				if json.Unmarshal(content, &parts) != nil {
					return nil, errors.New("invalid text content")
				}
				for _, part := range parts {
					if part.Type != "text" {
						return nil, errors.New("text only")
					}
					text += part.Text
				}
			}
			if text != "" {
				input = append(input, map[string]any{"role": role, "content": text})
			}
		}
		if raw, ok := msg["tool_calls"]; ok {
			var calls []struct {
				ID       string `json:"id"`
				Type     string `json:"type"`
				Function struct {
					Name      string `json:"name"`
					Arguments string `json:"arguments"`
				} `json:"function"`
			}
			if role != "assistant" || json.Unmarshal(raw, &calls) != nil {
				return nil, errors.New("invalid tool calls")
			}
			for _, call := range calls {
				if call.Type != "function" || call.ID == "" || call.Function.Name == "" {
					return nil, errors.New("invalid function call")
				}
				input = append(input, map[string]any{"type": "function_call", "call_id": call.ID, "name": call.Function.Name, "arguments": call.Function.Arguments})
			}
		}
	}
	out := map[string]json.RawMessage{"model": chat["model"], "stream": chat["stream"], "store": json.RawMessage(`false`)}
	if len(out["stream"]) == 0 {
		out["stream"] = json.RawMessage(`false`)
	}
	out["input"], _ = json.Marshal(input)
	out["max_output_tokens"] = chat["max_completion_tokens"]

	if effort, ok := chat["reasoning_effort"]; ok {
		out["reasoning"], _ = json.Marshal(map[string]json.RawMessage{"effort": effort})
	}
	for _, key := range []string{"parallel_tool_calls", "tool_choice"} {
		if v, ok := chat[key]; ok {
			out[key] = v
		}
	}
	if raw, ok := chat["tools"]; ok {
		var tools []struct {
			Type     string                     `json:"type"`
			Function map[string]json.RawMessage `json:"function"`
		}
		if json.Unmarshal(raw, &tools) != nil {
			return nil, errors.New("invalid tools")
		}
		converted := []map[string]json.RawMessage{}
		for _, tool := range tools {
			if tool.Type != "function" || tool.Function == nil {
				return nil, errors.New("function tools only")
			}
			tool.Function["type"] = json.RawMessage(`"function"`)
			// Preserve the existing optional parameters; Responses otherwise defaults to strict schemas.
			tool.Function["strict"] = json.RawMessage(`false`)
			converted = append(converted, tool.Function)
		}
		out["tools"], _ = json.Marshal(converted)
	}
	if raw, ok := out["tool_choice"]; ok && len(raw) > 0 && raw[0] == '{' {
		var choice struct {
			Type     string `json:"type"`
			Function struct {
				Name string `json:"name"`
			} `json:"function"`
		}
		if json.Unmarshal(raw, &choice) != nil || choice.Type != "function" || choice.Function.Name == "" {
			return nil, errors.New("invalid tool choice")
		}
		out["tool_choice"], _ = json.Marshal(map[string]string{"type": "function", "name": choice.Function.Name})
	}
	return out, nil
}

type aiResponse struct {
	ID     string `json:"id"`
	Model  string `json:"model"`
	Status string `json:"status"`
	Output []struct {
		Type      string `json:"type"`
		CallID    string `json:"call_id"`
		Name      string `json:"name"`
		Arguments string `json:"arguments"`
		Content   []struct {
			Type string `json:"type"`
			Text string `json:"text"`
		} `json:"content"`
	} `json:"output"`
	Usage *struct {
		Input   int64 `json:"input_tokens"`
		Output  int64 `json:"output_tokens"`
		Details struct {
			Cached int64 `json:"cached_tokens"`
		} `json:"input_tokens_details"`
	} `json:"usage"`
}

func (r aiResponse) usage() any {
	if r.Usage == nil {
		return nil
	}
	return map[string]any{"prompt_tokens": r.Usage.Input, "completion_tokens": r.Usage.Output, "prompt_tokens_details": map[string]int64{"cached_tokens": r.Usage.Details.Cached}}
}
func (r aiResponse) message() (map[string]any, string) {
	text := ""
	calls := []any{}
	for _, item := range r.Output {
		if item.Type == "message" {
			for _, part := range item.Content {
				if part.Type == "output_text" {
					text += part.Text
				}
			}
		}
		if item.Type == "function_call" {
			calls = append(calls, map[string]any{"index": len(calls), "id": item.CallID, "type": "function", "function": map[string]string{"name": item.Name, "arguments": item.Arguments}})
		}
	}
	msg := map[string]any{"role": "assistant", "content": text}
	finish := "stop"
	if len(calls) > 0 {
		msg["tool_calls"] = calls
		finish = "tool_calls"
	}
	if r.Status != "completed" {
		finish = "length"
		delete(msg, "tool_calls")
	}
	return msg, finish
}

// Translate the upstream wire format only. Existing clients retain their tool
// approval, cancellation and incomplete-stream safeguards, and quota settlement
// sees the same normalized usage as before. Never replay a failed model request.
func translateAIResponses(body io.Reader, stream bool, dst io.Writer) error {
	if !stream {
		var r aiResponse
		if err := json.NewDecoder(io.LimitReader(body, 8<<20)).Decode(&r); err != nil {
			return err
		}
		if r.Status != "completed" {
			return json.NewEncoder(dst).Encode(map[string]any{"error": map[string]string{"code": "response_incomplete"}, "usage": r.usage()})
		}
		msg, finish := r.message()
		return json.NewEncoder(dst).Encode(map[string]any{"id": r.ID, "model": r.Model, "choices": []any{map[string]any{"index": 0, "message": msg, "finish_reason": finish}}, "usage": r.usage()})
	}
	send := func(v any) error {
		b, err := json.Marshal(v)
		if err != nil {
			return err
		}
		_, err = fmt.Fprintf(dst, "data: %s\n\n", b)
		return err
	}
	scan := bufio.NewScanner(io.LimitReader(body, 8<<20))
	scan.Buffer(make([]byte, 4096), 1<<20)
	var lines []string
	consume := func() (bool, error) {
		if len(lines) == 0 {
			return false, nil
		}
		raw := strings.Join(lines, "\n")
		lines = nil
		var event struct {
			Type     string     `json:"type"`
			Delta    string     `json:"delta"`
			Response aiResponse `json:"response"`
		}
		if err := json.Unmarshal([]byte(raw), &event); err != nil {
			return false, err
		}
		switch event.Type {
		case "response.created", "response.in_progress", "response.output_item.added", "response.function_call_arguments.delta", "response.reasoning_text.delta", "response.reasoning_summary_text.delta":
			return false, send(map[string]any{"choices": []any{}})
		case "response.output_text.delta":
			return false, send(map[string]any{"choices": []any{map[string]any{"index": 0, "delta": map[string]string{"content": event.Delta}}}})
		case "response.completed", "response.incomplete", "response.failed":
			r := event.Response
			if err := send(map[string]any{"id": r.ID, "model": r.Model, "choices": []any{}, "usage": r.usage()}); err != nil {
				return false, err
			}
			if event.Type != "response.completed" || r.Status != "completed" {
				return false, errors.New("incomplete response")
			}
			msg, finish := r.message()
			delete(msg, "content") // Text has already been streamed.
			if err := send(map[string]any{"id": r.ID, "model": r.Model, "choices": []any{map[string]any{"index": 0, "delta": msg, "finish_reason": finish}}}); err != nil {
				return false, err
			}
			_, err := io.WriteString(dst, "data: [DONE]\n\n")
			return true, err
		case "error":
			return false, errors.New("upstream stream failed")
		}
		return false, nil
	}
	for scan.Scan() {
		line := scan.Text()
		if line == "" {
			done, err := consume()
			if err != nil {
				return err
			}
			if done {
				return nil
			}
		} else if strings.HasPrefix(line, "data:") {
			lines = append(lines, strings.TrimSpace(line[5:]))
		}
	}
	if err := scan.Err(); err != nil {
		return err
	}
	return io.ErrUnexpectedEOF
}

func aiResponsesBody(body io.ReadCloser, stream bool) io.ReadCloser {
	reader, writer := io.Pipe()
	go func() {
		defer body.Close()
		err := translateAIResponses(body, stream, writer)
		if err != nil && stream {
			_, _ = io.Copy(writer, bytes.NewBufferString("data: {\"error\":{\"code\":\"response_incomplete\"}}\n\n"))
		}
		_ = writer.CloseWithError(err)
	}()
	return reader
}
