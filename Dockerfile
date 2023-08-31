FROM --platform=$BUILDPLATFORM golang:1.20 AS builder

WORKDIR /go/src/github.com/Octops/octops-fleet-gc

COPY go.mod go.sum ./
RUN go mod download

COPY . .

ARG TARGETOS
ARG TARGETARCH

RUN make build && chmod +x /go/src/github.com/Octops/octops-fleet-gc/bin/octops-fleet-gc

FROM gcr.io/distroless/static:nonroot

WORKDIR /app

COPY --from=builder /go/src/github.com/Octops/octops-fleet-gc/bin/octops-fleet-gc /app/

ENTRYPOINT ["./octops-fleet-gc"]
