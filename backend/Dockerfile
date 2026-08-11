FROM golang:1.25-alpine AS build

RUN apk add --no-cache build-base
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=1 go build -trimpath -ldflags='-s -w' -o /out/ianvs-api ./cmd/ianvs-api

FROM alpine:3.22

RUN apk add --no-cache ca-certificates tzdata \
    && addgroup -S ianvs \
    && adduser -S -G ianvs -h /var/lib/ianvs ianvs
COPY --from=build /out/ianvs-api /usr/local/bin/ianvs-api
USER ianvs
WORKDIR /var/lib/ianvs
EXPOSE 47832
ENTRYPOINT ["ianvs-api"]
CMD ["serve"]
