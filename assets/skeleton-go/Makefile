# Build the plugin for the current platform.
# Mirrors the extension logic in examples/plugin/Makefile.

PLUGIN_ID := __PLUGIN_ID__
BIN_DIR   := $(CURDIR)/bin
UNAME_S   := $(shell uname -s)

ifeq ($(OS),Windows_NT)
PLUGIN_EXT := dll
else ifeq ($(UNAME_S),Darwin)
PLUGIN_EXT := dylib
else
PLUGIN_EXT := so
endif

TARGET := $(BIN_DIR)/$(PLUGIN_ID).$(PLUGIN_EXT)

.PHONY: build clean fmt

build: $(TARGET)

$(BIN_DIR):
	mkdir -p $(BIN_DIR)

# The .h file emitted alongside the shared library is not needed for
# distribution; the host resolves symbols by name.
$(TARGET): main.go go.mod | $(BIN_DIR)
	go build -buildmode=c-shared -o $(TARGET) .
	$(RM) $(BIN_DIR)/$(PLUGIN_ID).h

fmt:
	gofmt -w .

clean:
	$(RM) -r $(BIN_DIR)
