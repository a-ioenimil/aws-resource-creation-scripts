.PHONY: build install run clean deps

build:
	@echo "🔨 Building aws-automator..."
	@go build -o bin/aws-automator cmd/aws-automator/main.go
	@echo "✅ Build complete: bin/aws-automator"

install: build
	@echo "📦 Installing aws-automator..."
	@sudo cp bin/aws-automator /usr/local/bin/
	@echo "✅ Installed to /usr/local/bin/aws-automator"

run: build
	@./bin/aws-automator interactive

clean:
	@echo "🧹 Cleaning build artifacts..."
	@rm -rf bin/
	@echo "✅ Clean complete"

deps:
	@echo "📥 Downloading dependencies..."
	@go mod tidy
	@echo "✅ Dependencies downloaded"
