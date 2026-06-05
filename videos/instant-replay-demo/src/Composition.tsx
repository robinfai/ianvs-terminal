import React from "react";
import {
  AbsoluteFill,
  Easing,
  Img,
  interpolate,
  staticFile,
  useCurrentFrame,
} from "remotion";
import {
  Check,
  ChevronDown,
  ChevronUp,
  Clock,
  Copy,
  History,
  Maximize2,
  MousePointer2,
  Pause,
  Play,
  Search,
  SkipBack,
  SkipForward,
  SquareTerminal,
  Trash2,
  X,
  type LucideIcon,
} from "lucide-react";

type TerminalStep = {
  label: string;
  lines: string[];
  cursorRow: number;
};

const colors = {
  canvas: "#07080a",
  panel: "#111214",
  panelRaised: "#2d2d30",
  terminal: "#020304",
  border: "#3b3c40",
  borderSoft: "rgba(255, 255, 255, 0.12)",
  text: "#f5f5f7",
  textMuted: "#a6a6ad",
  textFaint: "#73747b",
  blue: "#0a84ff",
  cyan: "#54d2ff",
  green: "#a6e3a1",
  amber: "#ffd166",
  pink: "#ff8fb3",
  purple: "#b9a7ff",
};

const terminalSteps: TerminalStep[] = [
  {
    label: "Frame 1",
    cursorRow: 1,
    lines: [
      "robinfai  ~  14:16  >",
      "",
      "",
      "",
      "",
      "",
      "",
      "",
      "",
    ],
  },
  {
    label: "Frame 14",
    cursorRow: 4,
    lines: [
      "robinfai  ~/ianvs-terminal  14:16  > flutter test example/test/shell/shell_screen_instant_replay_test.dart",
      "00:00 +0: loading example/test/shell/shell_screen_instant_replay_test.dart",
      "00:01 +3: replay workspace renders latest terminal frame",
      "00:02 +6: timeline slider seeks to recorded frame",
      "",
      "",
      "",
      "",
      "",
    ],
  },
  {
    label: "Frame 27",
    cursorRow: 7,
    lines: [
      "robinfai  ~/ianvs-terminal  14:16  > flutter test example/test/shell/shell_screen_instant_replay_test.dart",
      "00:01 +3: replay workspace renders latest terminal frame",
      "00:02 +6: timeline slider seeks to recorded frame",
      "00:03 +8: replay search jumps to matching terminal output",
      "00:04 +10: copy visible replay text records paste history",
      "00:04 +11: clear history leaves live session running",
      "",
      "",
      "",
    ],
  },
  {
    label: "Frame 38",
    cursorRow: 8,
    lines: [
      "robinfai  ~/ianvs-terminal  14:16  > flutter test example/test/shell/shell_screen_instant_replay_test.dart",
      "00:02 +6: timeline slider seeks to recorded frame",
      "00:03 +8: replay search jumps to matching terminal output",
      "00:04 +10: copy visible replay text records paste history",
      "00:04 +11: clear history leaves live session running",
      "00:05 +11: All tests passed!",
      "robinfai  ~/ianvs-terminal  14:17  >",
      "",
      "",
    ],
  },
];

const clamp = (value: number, min: number, max: number) => {
  return Math.min(Math.max(value, min), max);
};

const eased = (frame: number, input: [number, number], output: [number, number]) =>
  interpolate(frame, input, output, {
    easing: Easing.bezier(0.16, 1, 0.3, 1),
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

const sceneOpacity = (
  frame: number,
  start: number,
  end: number,
  fadeFrames = 22,
) => {
  const fadeIn = eased(frame, [start, start + fadeFrames], [0, 1]);
  const fadeOut = eased(frame, [end - fadeFrames, end], [1, 0]);
  return Math.min(fadeIn, fadeOut);
};

const slideUp = (frame: number, start: number, distance = 36) => {
  return eased(frame, [start, start + 34], [distance, 0]);
};

const typingText = (frame: number, start: number, text: string, charsPerSecond = 9) => {
  const fps = 30;
  const chars = Math.floor(((frame - start) / fps) * charsPerSecond);
  return text.slice(0, clamp(chars, 0, text.length));
};

const IconButton: React.FC<{
  icon: LucideIcon;
  label: string;
  active?: boolean;
  filled?: boolean;
  disabled?: boolean;
}> = ({ icon: Icon, label, active, filled, disabled }) => {
  return (
    <div
      style={{
        width: 54,
        height: 54,
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        borderRadius: 12,
        color: disabled ? colors.textFaint : active || filled ? colors.text : colors.textMuted,
        background: filled
          ? colors.blue
          : active
            ? "rgba(10, 132, 255, 0.18)"
            : "rgba(255, 255, 255, 0.04)",
        border: `1px solid ${active ? "rgba(10, 132, 255, 0.72)" : colors.borderSoft}`,
      }}
      title={label}
    >
      <Icon size={28} strokeWidth={2.3} />
    </div>
  );
};

const Pill: React.FC<{
  children: React.ReactNode;
  tone?: "blue" | "green" | "amber" | "pink" | "neutral";
}> = ({ children, tone = "neutral" }) => {
  const map = {
    blue: ["rgba(10, 132, 255, 0.18)", colors.blue],
    green: ["rgba(166, 227, 161, 0.16)", colors.green],
    amber: ["rgba(255, 209, 102, 0.16)", colors.amber],
    pink: ["rgba(255, 143, 179, 0.16)", colors.pink],
    neutral: ["rgba(255, 255, 255, 0.06)", colors.textMuted],
  } as const;

  return (
    <div
      style={{
        display: "inline-flex",
        alignItems: "center",
        height: 44,
        padding: "0 18px",
        borderRadius: 11,
        border: `1px solid ${colors.borderSoft}`,
        background: map[tone][0],
        color: map[tone][1],
        fontSize: 24,
        fontWeight: 700,
        whiteSpace: "nowrap",
      }}
    >
      {children}
    </div>
  );
};

const Stage: React.FC<{ children: React.ReactNode }> = ({ children }) => (
  <AbsoluteFill
    style={{
      background: colors.canvas,
      color: colors.text,
      fontFamily:
        "-apple-system, BlinkMacSystemFont, 'SF Pro Display', 'PingFang SC', 'Segoe UI', sans-serif",
      overflow: "hidden",
    }}
  >
    <div
      style={{
        position: "absolute",
        inset: 0,
        backgroundImage:
          "linear-gradient(rgba(255,255,255,0.04) 1px, transparent 1px), linear-gradient(90deg, rgba(255,255,255,0.035) 1px, transparent 1px)",
        backgroundSize: "64px 64px",
        opacity: 0.28,
      }}
    />
    <div
      style={{
        position: "absolute",
        inset: 0,
        background:
          "radial-gradient(circle at 16% 14%, rgba(255, 143, 179, 0.18), transparent 28%), radial-gradient(circle at 86% 72%, rgba(84, 210, 255, 0.16), transparent 32%)",
      }}
    />
    {children}
  </AbsoluteFill>
);

const ProductWindow: React.FC<{
  children: React.ReactNode;
  width?: number;
  height?: number;
  title?: string;
  style?: React.CSSProperties;
}> = ({ children, width = 1510, height = 850, title = "Ianvs Terminal", style }) => (
  <div
    style={{
      width,
      height,
      borderRadius: 28,
      border: `1px solid ${colors.borderSoft}`,
      background: colors.terminal,
      boxShadow: "0 34px 90px rgba(0,0,0,0.48)",
      overflow: "hidden",
      ...style,
    }}
  >
    <div
      style={{
        height: 68,
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        borderBottom: `1px solid ${colors.borderSoft}`,
        color: colors.textMuted,
        fontSize: 28,
        fontWeight: 700,
      }}
    >
      <span style={{ color: colors.textFaint, marginRight: 10 }}>⌘1</span>
      {title}
      <span style={{ color: colors.textFaint, marginLeft: 12 }}>×</span>
    </div>
    {children}
  </div>
);

const ScreenshotWindow: React.FC<{
  src: string;
  width: number;
  height: number;
  style?: React.CSSProperties;
}> = ({ src, width, height, style }) => (
  <div
    style={{
      width,
      height,
      borderRadius: 28,
      overflow: "hidden",
      border: `1px solid ${colors.borderSoft}`,
      boxShadow: "0 32px 90px rgba(0,0,0,0.48)",
      background: colors.terminal,
      ...style,
    }}
  >
    <Img
      src={staticFile(src)}
      style={{
        width: "100%",
        height: "100%",
        objectFit: "cover",
        display: "block",
      }}
    />
  </div>
);

const CaptionBlock: React.FC<{
  eyebrow: string;
  title: string;
  body: string;
  align?: "left" | "right";
}> = ({ eyebrow, title, body, align = "left" }) => (
  <div
    style={{
      width: 560,
      textAlign: align,
    }}
  >
    <div
      style={{
        color: colors.cyan,
        fontSize: 25,
        fontWeight: 800,
        marginBottom: 18,
      }}
    >
      {eyebrow}
    </div>
    <div
      style={{
        fontSize: 76,
        lineHeight: 1.02,
        fontWeight: 860,
        marginBottom: 26,
      }}
    >
      {title}
    </div>
    <div
      style={{
        color: colors.textMuted,
        fontSize: 31,
        lineHeight: 1.45,
        fontWeight: 600,
      }}
    >
      {body}
    </div>
  </div>
);

const Prompt: React.FC = () => (
  <div
    style={{
      display: "flex",
      alignItems: "center",
      height: 50,
      fontFamily: "'SF Mono', Menlo, Monaco, Consolas, monospace",
      fontSize: 23,
      fontWeight: 800,
    }}
  >
    {[
      ["#ff8fb3", " robinfai"],
      ["#f1a469", "~"],
      ["#a6e3a1", ""],
      ["#54d2ff", ""],
      ["#b9a7ff", "◷ 14:16"],
    ].map(([background, text], index) => (
      <div
        key={`${background}-${index}`}
        style={{
          height: 50,
          minWidth: index === 2 || index === 3 ? 42 : undefined,
          padding: text ? "0 20px" : "0 14px",
          display: "flex",
          alignItems: "center",
          background,
          color: "#050608",
          clipPath:
            index === 0
              ? "polygon(0 0, calc(100% - 18px) 0, 100% 50%, calc(100% - 18px) 100%, 0 100%)"
              : "polygon(0 0, calc(100% - 18px) 0, 100% 50%, calc(100% - 18px) 100%, 0 100%, 18px 50%)",
          marginLeft: index === 0 ? 0 : -13,
        }}
      >
        {text}
      </div>
    ))}
    <div style={{ color: "#83a68b", fontSize: 38, marginLeft: 22 }}>›</div>
    <div
      style={{
        width: 18,
        height: 44,
        background: "#9bbfa1",
        marginLeft: 16,
      }}
    />
  </div>
);

const IntroScene: React.FC<{ opacity: number; frame: number }> = ({ opacity, frame }) => {
  const imageY = slideUp(frame, 12, 30);
  const titleY = slideUp(frame, 28, 44);

  return (
    <AbsoluteFill style={{ opacity }}>
      <div
        style={{
          position: "absolute",
          left: 110,
          top: 140 + titleY,
        }}
      >
        <CaptionBlock
          eyebrow="Ianvs Terminal"
          title="Instant Replay"
          body="把刚刚发生的终端画面取出来回看，不打断正在运行的 live session。"
        />
        <div style={{ display: "flex", gap: 14, marginTop: 38 }}>
          <Pill tone="blue">timeline</Pill>
          <Pill tone="green">search</Pill>
          <Pill tone="amber">copy</Pill>
        </div>
      </div>
      <ScreenshotWindow
        src="product/launch-prompt.png"
        width={980}
        height={735}
        style={{
          position: "absolute",
          right: 112,
          top: 170 + imageY,
          transform: `scale(${eased(frame, [12, 82], [0.96, 1.02])})`,
          transformOrigin: "center",
        }}
      />
      <div
        style={{
          position: "absolute",
          right: 202,
          bottom: 168,
          display: "flex",
          alignItems: "center",
          gap: 16,
          padding: "16px 22px",
          borderRadius: 18,
          background: "rgba(17, 18, 20, 0.86)",
          border: `1px solid ${colors.borderSoft}`,
          color: colors.textMuted,
          fontSize: 24,
          fontWeight: 750,
        }}
      >
        <History size={30} color={colors.blue} />
        Recent terminal frames are ready
      </div>
    </AbsoluteFill>
  );
};

const OpenReplayScene: React.FC<{ opacity: number; frame: number }> = ({ opacity, frame }) => {
  const typed = typingText(frame, 175, "replay", 8);
  const menuProgress = eased(frame, [150, 210], [0, 1]);
  const pointerX = eased(frame, [222, 255], [1180, 1270]);
  const pointerY = eased(frame, [222, 255], [392, 512]);

  return (
    <AbsoluteFill style={{ opacity }}>
      <ScreenshotWindow
        src="product/command-menu.png"
        width={1250}
        height={938}
        style={{
          position: "absolute",
          left: 90,
          top: 82,
          transform: `translateX(${eased(frame, [140, 190], [-42, 0])}px) scale(0.98)`,
          transformOrigin: "left center",
        }}
      />
      <div
        style={{
          position: "absolute",
          right: 100,
          top: 146,
          width: 650,
          borderRadius: 28,
          padding: 30,
          background: "rgba(45, 45, 48, 0.96)",
          border: `2px solid rgba(255,255,255,${0.16 + menuProgress * 0.18})`,
          boxShadow: "0 34px 100px rgba(0,0,0,0.48)",
          transform: `translateY(${(1 - menuProgress) * 42}px)`,
        }}
      >
        <div
          style={{
            display: "flex",
            alignItems: "center",
            justifyContent: "space-between",
            marginBottom: 24,
          }}
        >
          <div style={{ fontSize: 35, fontWeight: 850 }}>Top actions</div>
          <X size={34} color={colors.textMuted} />
        </div>
        <div
          style={{
            height: 90,
            borderRadius: 15,
            border: `4px solid ${colors.blue}`,
            display: "flex",
            alignItems: "center",
            padding: "0 24px",
            gap: 20,
            fontSize: 31,
            fontWeight: 700,
            color: colors.text,
          }}
        >
          <Search size={38} />
          <span>{typed}</span>
          <span
            style={{
              width: 4,
              height: 38,
              background: colors.blue,
              opacity: Math.sin(frame / 5) > 0 ? 1 : 0.25,
            }}
          />
        </div>
        <div
          style={{
            marginTop: 26,
            display: "grid",
            gridTemplateColumns: "64px 1fr auto",
            gap: 18,
            alignItems: "center",
            padding: "20px 14px",
            borderRadius: 18,
            background: "rgba(10, 132, 255, 0.14)",
            border: `2px solid rgba(10,132,255,${0.44 + Math.sin(frame / 9) * 0.14})`,
          }}
        >
          <History size={50} color={colors.blue} />
          <div>
            <div style={{ fontSize: 33, fontWeight: 850 }}>Instant Replay</div>
            <div style={{ marginTop: 8, fontSize: 23, color: colors.textMuted, fontWeight: 650 }}>
              Open a replay workspace for this terminal.
            </div>
          </div>
          <div style={{ color: colors.textMuted, fontSize: 27, fontWeight: 800 }}>↵</div>
        </div>
      </div>
      <div
        style={{
          position: "absolute",
          left: pointerX,
          top: pointerY,
          color: colors.text,
          transform: "rotate(-12deg)",
          filter: "drop-shadow(0 14px 22px rgba(0,0,0,0.55))",
        }}
      >
        <MousePointer2 size={54} fill={colors.text} />
      </div>
      <div
        style={{
          position: "absolute",
          left: 130,
          bottom: 96,
          width: 710,
          fontSize: 34,
          lineHeight: 1.35,
          color: colors.textMuted,
          fontWeight: 700,
        }}
      >
        从当前 pane 打开回放。原来的终端不被替换，也不会收到 replay 里的按键。
      </div>
    </AbsoluteFill>
  );
};

const ReplayWorkspaceScene: React.FC<{
  opacity: number;
  frame: number;
  mode: "playback" | "search" | "actions" | "empty";
}> = ({ opacity, frame, mode }) => {
  const entry = eased(frame, [292, 346], [0, 1]);
  const playProgress = mode === "playback" ? eased(frame, [336, 470], [0.08, 0.92]) : 0.74;
  const searchProgress = mode === "search" ? eased(frame, [520, 592], [0, 1]) : 0;
  const emptyProgress = mode === "empty" ? eased(frame, [676, 720], [0, 1]) : 0;
  const copied = mode === "actions" && frame > 630 && frame < 675;
  const activeStep =
    mode === "empty"
      ? terminalSteps[3]
      : terminalSteps[
          clamp(Math.floor(playProgress * terminalSteps.length), 0, terminalSteps.length - 1)
        ];

  return (
    <AbsoluteFill style={{ opacity }}>
      <div
        style={{
          position: "absolute",
          left: 120,
          top: 76,
          display: "flex",
          alignItems: "center",
          gap: 14,
          transform: `translateY(${(1 - entry) * 36}px)`,
          opacity: entry,
        }}
      >
        <SquareTerminal size={34} color={colors.cyan} />
        <div style={{ fontSize: 31, color: colors.textMuted, fontWeight: 760 }}>
          Instant Replay workspace
        </div>
      </div>
      <ProductWindow
        width={1680}
        height={850}
        title="Replay mode"
        style={{
          position: "absolute",
          left: 120,
          top: 142,
          transform: `translateY(${(1 - entry) * 60}px) scale(${0.985 + entry * 0.015})`,
          opacity: entry,
        }}
      >
        <div style={{ height: 782, padding: 22, display: "flex", flexDirection: "column", gap: 20 }}>
          <ReplayViewport
            step={activeStep}
            searchProgress={searchProgress}
            emptyProgress={emptyProgress}
          />
          <ReplayControls
            frame={frame}
            mode={mode}
            playProgress={mode === "search" ? 0.64 + searchProgress * 0.12 : playProgress}
            copied={copied}
          />
        </div>
      </ProductWindow>
      {mode === "playback" ? (
        <div
          style={{
            position: "absolute",
            right: 126,
            top: 86,
            width: 520,
            fontSize: 34,
            lineHeight: 1.34,
            color: colors.textMuted,
            fontWeight: 720,
            textAlign: "right",
          }}
        >
          播放、跳帧、拖动时间线，都只移动回放画面。
        </div>
      ) : null}
      {mode === "search" ? (
        <div
          style={{
            position: "absolute",
            right: 132,
            top: 90,
            display: "flex",
            gap: 12,
          }}
        >
          <Pill tone="blue">4 matches</Pill>
          <Pill tone="pink">38 frames</Pill>
        </div>
      ) : null}
    </AbsoluteFill>
  );
};

const ReplayViewport: React.FC<{
  step: TerminalStep;
  searchProgress: number;
  emptyProgress: number;
}> = ({ step, searchProgress, emptyProgress }) => {
  return (
    <div
      style={{
        flex: 1,
        borderRadius: 18,
        border: `1px solid ${colors.borderSoft}`,
        background: colors.terminal,
        overflow: "hidden",
        position: "relative",
      }}
    >
      <div
        style={{
          position: "absolute",
          inset: 0,
          padding: 24,
          opacity: 1 - emptyProgress,
          fontFamily: "'SF Mono', Menlo, Monaco, Consolas, monospace",
        }}
      >
        <Prompt />
        <div style={{ marginTop: 22, fontSize: 25, lineHeight: "40px", color: "#d8d8de" }}>
          {step.lines.map((line, index) => (
            <TerminalLine
              key={`${step.label}-${index}-${line}`}
              line={line}
              highlight={searchProgress > 0.2 && line.toLowerCase().includes("replay")}
              active={searchProgress > 0.72 && index === 2}
            />
          ))}
        </div>
      </div>
      <div
        style={{
          position: "absolute",
          inset: 0,
          opacity: emptyProgress,
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          flexDirection: "column",
          gap: 24,
          color: colors.textMuted,
          fontSize: 30,
          fontWeight: 750,
        }}
      >
        <History size={64} color={colors.textFaint} />
        No replay frames captured yet.
      </div>
      <div
        style={{
          position: "absolute",
          right: 20,
          top: 18,
          display: "flex",
          gap: 10,
          opacity: 1 - emptyProgress,
        }}
      >
        <Pill tone="neutral">Recorded at 93x22</Pill>
        <Pill tone="green">read-only</Pill>
      </div>
    </div>
  );
};

const TerminalLine: React.FC<{
  line: string;
  highlight?: boolean;
  active?: boolean;
}> = ({ line, highlight, active }) => {
  if (!highlight) {
    return <div style={{ minHeight: 40 }}>{line}</div>;
  }

  const parts = line.split(/(replay)/i);
  return (
    <div style={{ minHeight: 40 }}>
      {parts.map((part, index) => {
        const isMatch = part.toLowerCase() === "replay";
        return (
          <span
            key={`${part}-${index}`}
            style={
              isMatch
                ? {
                    color: colors.text,
                    background: active ? "rgba(10,132,255,0.42)" : "rgba(255,209,102,0.28)",
                    border: active ? `2px solid ${colors.blue}` : "2px solid transparent",
                    borderRadius: 5,
                    padding: "1px 4px",
                  }
                : undefined
            }
          >
            {part}
          </span>
        );
      })}
    </div>
  );
};

const ReplayControls: React.FC<{
  frame: number;
  mode: "playback" | "search" | "actions" | "empty";
  playProgress: number;
  copied: boolean;
}> = ({ frame, mode, playProgress, copied }) => {
  const searchText = mode === "search" ? typingText(frame, 514, "replay", 10) : "";
  const pulse = 0.5 + Math.sin(frame / 7) * 0.5;
  const isPlaying = mode === "playback" && frame < 482;
  const empty = mode === "empty";

  return (
    <div
      style={{
        minHeight: 236,
        borderRadius: 18,
        border: `1px solid ${colors.borderSoft}`,
        background: "rgba(45, 45, 48, 0.94)",
        padding: 22,
        display: "grid",
        gridTemplateColumns: "1fr auto",
        gap: 18,
      }}
    >
      <div style={{ display: "flex", flexDirection: "column", gap: 16 }}>
        <div style={{ display: "flex", alignItems: "center", gap: 16 }}>
          <History size={30} color={colors.blue} />
          <div style={{ fontSize: 31, fontWeight: 850 }}>Replay mode</div>
          <div
            style={{
              flex: 1,
              color: colors.textMuted,
              fontSize: 22,
              fontWeight: 650,
              overflow: "hidden",
              whiteSpace: "nowrap",
              textOverflow: "ellipsis",
            }}
          >
            Local Shell / zsh / pane 1 • Recorded at 93x22 • 14:16:{empty ? "18" : "08"}
          </div>
        </div>
        <Timeline progress={empty ? 0 : playProgress} frame={frame} dim={empty} />
        <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
          <div
            style={{
              height: 62,
              flex: 1,
              borderRadius: 14,
              border: `2px solid ${mode === "search" ? colors.blue : colors.border}`,
              display: "flex",
              alignItems: "center",
              padding: "0 18px",
              gap: 14,
              color: mode === "search" ? colors.text : colors.textMuted,
              fontSize: 25,
              fontWeight: 720,
              background: "rgba(17, 18, 20, 0.58)",
            }}
          >
            <Search size={30} />
            <span>{searchText || "Search replay"}</span>
            {mode === "search" ? (
              <span
                style={{
                  width: 3,
                  height: 30,
                  background: colors.blue,
                  opacity: pulse > 0.3 ? 1 : 0.3,
                }}
              />
            ) : null}
          </div>
          <IconButton icon={ChevronUp} label="Previous search match" disabled={mode !== "search"} />
          <IconButton icon={ChevronDown} label="Next search match" active={mode === "search"} />
          <div
            style={{
              minWidth: 284,
              color: mode === "search" ? colors.textMuted : "transparent",
              fontSize: 22,
              fontWeight: 700,
            }}
          >
            4 matches across 38 frames
          </div>
        </div>
      </div>
      <div style={{ display: "flex", flexDirection: "column", justifyContent: "space-between" }}>
        <div style={{ display: "flex", gap: 10, justifyContent: "flex-end" }}>
          <IconButton icon={SkipBack} label="Step back" disabled={empty} />
          <IconButton icon={isPlaying ? Pause : Play} label={isPlaying ? "Pause replay" : "Play replay"} active={mode === "playback"} disabled={empty} />
          <IconButton icon={SkipForward} label="Step forward" disabled={empty} />
          <IconButton icon={Maximize2} label="Fit recorded size" disabled={empty} />
          <IconButton icon={Copy} label="Copy visible" filled={mode === "actions"} disabled={empty} />
          <IconButton icon={Trash2} label="Clear history" active={mode === "empty"} disabled={false} />
          <IconButton icon={X} label="Exit replay" />
        </div>
        <div
          style={{
            alignSelf: "flex-end",
            opacity: copied ? 1 : 0,
            transform: `translateY(${copied ? 0 : 14}px)`,
            display: "flex",
            alignItems: "center",
            gap: 12,
            padding: "13px 18px",
            borderRadius: 14,
            background: "rgba(166, 227, 161, 0.15)",
            color: colors.green,
            fontSize: 22,
            fontWeight: 800,
            border: "1px solid rgba(166, 227, 161, 0.28)",
          }}
        >
          <Check size={26} />
          Visible text copied
        </div>
      </div>
    </div>
  );
};

const Timeline: React.FC<{ progress: number; frame: number; dim?: boolean }> = ({
  progress,
  frame,
  dim,
}) => {
  const markerPositions = [0.04, 0.11, 0.2, 0.32, 0.47, 0.64, 0.78, 0.92];

  return (
    <div style={{ height: 56, position: "relative", opacity: dim ? 0.34 : 1 }}>
      <div
        style={{
          position: "absolute",
          left: 8,
          right: 8,
          top: 14,
          height: 12,
          borderRadius: 6,
          background: "rgba(255,255,255,0.12)",
          overflow: "hidden",
        }}
      >
        <div
          style={{
            width: `${clamp(progress, 0, 1) * 100}%`,
            height: "100%",
            background: `linear-gradient(90deg, ${colors.blue}, ${colors.cyan}, ${colors.green})`,
          }}
        />
      </div>
      {markerPositions.map((position, index) => (
        <div
          key={position}
          style={{
            position: "absolute",
            left: `${position * 100}%`,
            top: index === 4 ? 2 : 7,
            width: index === 4 ? 9 : 6,
            height: index === 4 ? 36 : 25,
            borderRadius: 5,
            background: index === 4 ? colors.amber : "rgba(255,255,255,0.42)",
            opacity: 0.65 + Math.sin(frame / 12 + index) * 0.08,
          }}
        />
      ))}
      <div
        style={{
          position: "absolute",
          left: `${clamp(progress, 0, 1) * 100}%`,
          top: -1,
          width: 32,
          height: 32,
          marginLeft: -16,
          borderRadius: 16,
          border: `5px solid ${colors.text}`,
          background: colors.blue,
          boxShadow: "0 0 0 8px rgba(10,132,255,0.16)",
        }}
      />
      <div
        style={{
          position: "absolute",
          left: 0,
          bottom: 0,
          display: "flex",
          alignItems: "center",
          gap: 8,
          color: colors.textMuted,
          fontSize: 20,
          fontWeight: 700,
        }}
      >
        <Clock size={23} />
        {Math.round(1 + progress * 37)} of 38 frames
      </div>
    </div>
  );
};

const EndScene: React.FC<{ opacity: number; frame: number }> = ({ opacity, frame }) => {
  const y = slideUp(frame, 706, 42);

  return (
    <AbsoluteFill style={{ opacity }}>
      <div
        style={{
          position: "absolute",
          inset: 0,
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          flexDirection: "column",
          gap: 34,
          transform: `translateY(${y}px)`,
        }}
      >
        <div
          style={{
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            width: 108,
            height: 108,
            borderRadius: 26,
            border: `1px solid ${colors.borderSoft}`,
            background: "rgba(10, 132, 255, 0.16)",
          }}
        >
          <History size={62} color={colors.blue} />
        </div>
        <div
          style={{
            fontSize: 82,
            fontWeight: 880,
            textAlign: "center",
          }}
        >
          回看终端历史，不打断当前工作
        </div>
        <div
          style={{
            width: 780,
            textAlign: "center",
            color: colors.textMuted,
            fontSize: 34,
            lineHeight: 1.42,
            fontWeight: 680,
          }}
        >
          Instant Replay v1 专注最近文本帧：查看、搜索、复制、清空，和 live session 保持隔离。
        </div>
      </div>
    </AbsoluteFill>
  );
};

export const InstantReplayDemo: React.FC = () => {
  const frame = useCurrentFrame();

  return (
    <Stage>
      <IntroScene opacity={sceneOpacity(frame, 0, 164)} frame={frame} />
      <OpenReplayScene opacity={sceneOpacity(frame, 132, 296)} frame={frame} />
      <ReplayWorkspaceScene
        opacity={sceneOpacity(frame, 262, 512)}
        frame={frame}
        mode="playback"
      />
      <ReplayWorkspaceScene
        opacity={sceneOpacity(frame, 486, 630)}
        frame={frame}
        mode="search"
      />
      <ReplayWorkspaceScene
        opacity={sceneOpacity(frame, 604, 706)}
        frame={frame}
        mode="actions"
      />
      <ReplayWorkspaceScene
        opacity={sceneOpacity(frame, 674, 734)}
        frame={frame}
        mode="empty"
      />
      <EndScene opacity={sceneOpacity(frame, 708, 750, 18)} frame={frame} />
    </Stage>
  );
};
