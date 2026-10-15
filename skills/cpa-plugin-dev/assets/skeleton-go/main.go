// Package main is a minimal CLIProxyAPI plugin skeleton.
//
// Provenance: the cgo preamble, the exported symbol set, the init function
// and the response-buffer handling are taken from the official example at
// CLIProxyAPI源码/examples/plugin/simple/go/main.go. The capability set has
// been reduced to a single processing capability on purpose: declaring
// capabilities you do not implement makes the host call methods that will
// fail. Add one capability at a time.
//
// Replace every __PLACEHOLDER__ before building.
package main

/*
#include <stdint.h>
#include <stdlib.h>

typedef struct {
	void* ptr;
	size_t len;
} cliproxy_buffer;

typedef int (*cliproxy_host_call_fn)(void*, const char*, const uint8_t*, size_t, cliproxy_buffer*);
typedef void (*cliproxy_host_free_fn)(void*, size_t);

typedef struct {
	uint32_t abi_version;
	void* host_ctx;
	cliproxy_host_call_fn call;
	cliproxy_host_free_fn free_buffer;
} cliproxy_host_api;

typedef int (*cliproxy_plugin_call_fn)(char*, uint8_t*, size_t, cliproxy_buffer*);
typedef void (*cliproxy_plugin_free_fn)(void*, size_t);
typedef void (*cliproxy_plugin_shutdown_fn)(void);

typedef struct {
	uint32_t abi_version;
	cliproxy_plugin_call_fn call;
	cliproxy_plugin_free_fn free_buffer;
	cliproxy_plugin_shutdown_fn shutdown;
} cliproxy_plugin_api;

extern int cliproxyPluginCall(char*, uint8_t*, size_t, cliproxy_buffer*);
extern void cliproxyPluginFree(void*, size_t);
extern void cliproxyPluginShutdown(void);
*/
import "C"

import (
	"encoding/json"
	"unsafe"

	"github.com/router-for-me/CLIProxyAPI/v8/sdk/pluginabi"
	"github.com/router-for-me/CLIProxyAPI/v8/sdk/pluginapi"
)

const (
	pluginID      = "__PLUGIN_ID__"
	pluginVersion = "0.1.0"
	pluginAuthor  = "__AUTHOR__"
	pluginRepo    = "__REPOSITORY__"
	providerKey   = "__PROVIDER_KEY__"
)

// host holds the host function table captured at init time. Nested calls
// back into the host (host.http.*, host.model.*, host.log, ...) go through it.
var host struct {
	ctx  unsafe.Pointer
	call C.cliproxy_host_call_fn
}

type envelope struct {
	OK     bool             `json:"ok"`
	Result json.RawMessage  `json:"result,omitempty"`
	Error  *pluginabi.Error `json:"error,omitempty"`
}

func main() {}

//export cliproxy_plugin_init
func cliproxy_plugin_init(hostAPI *C.cliproxy_host_api, plugin *C.cliproxy_plugin_api) C.int {
	if plugin == nil {
		return 1
	}
	if hostAPI != nil {
		host.ctx = hostAPI.host_ctx
		host.call = hostAPI.call
	}
	plugin.abi_version = C.uint32_t(pluginabi.ABIVersion)
	plugin.call = C.cliproxy_plugin_call_fn(C.cliproxyPluginCall)
	plugin.free_buffer = C.cliproxy_plugin_free_fn(C.cliproxyPluginFree)
	plugin.shutdown = C.cliproxy_plugin_shutdown_fn(C.cliproxyPluginShutdown)
	return 0
}

//export cliproxyPluginCall
func cliproxyPluginCall(method *C.char, request *C.uint8_t, requestLen C.size_t, response *C.cliproxy_buffer) C.int {
	if response != nil {
		response.ptr = nil
		response.len = 0
	}
	if method == nil {
		writeResponse(response, errorEnvelope("invalid_method", "method is required", 0))
		return 1
	}
	var requestBytes []byte
	if request != nil && requestLen > 0 {
		requestBytes = C.GoBytes(unsafe.Pointer(request), C.int(requestLen))
	}
	raw, errHandle := handleMethod(C.GoString(method), requestBytes)
	if errHandle != nil {
		writeResponse(response, errorEnvelope("plugin_error", errHandle.Error(), 0))
		return 1
	}
	writeResponse(response, raw)
	return 0
}

//export cliproxyPluginFree
func cliproxyPluginFree(ptr unsafe.Pointer, len C.size_t) {
	if ptr != nil {
		C.free(ptr)
	}
}

//export cliproxyPluginShutdown
func cliproxyPluginShutdown() {}

func handleMethod(method string, request []byte) ([]byte, error) {
	switch method {
	// Registration and reconfiguration share one response. Read config_yaml
	// here and validate every plugin-owned field yourself: ConfigFields only
	// drives the management UI form, the host does not validate for you.
	case pluginabi.MethodPluginRegister, pluginabi.MethodPluginReconfigure:
		return okEnvelope(registration())

	// The single capability declared below.
	case pluginabi.MethodRequestNormalize:
		return handleNormalize(request)

	// Never omit this branch. The host reports a clearer error than a panic.
	default:
		return errorEnvelope("unknown_method", "unknown method: "+method, 0), nil
	}
}

func registration() map[string]any {
	return map[string]any{
		"schema_version": pluginabi.SchemaVersion,
		"metadata": pluginapi.Metadata{
			Name:             pluginID,
			Version:          pluginVersion,
			Author:           pluginAuthor,
			GitHubRepository: pluginRepo,
			ConfigFields: []pluginapi.ConfigField{
				{
					Name:        "enabled",
					Type:        pluginapi.ConfigFieldTypeBoolean,
					Description: "Managed by the host.",
				},
				{
					Name:        "mode",
					Type:        pluginapi.ConfigFieldTypeEnum,
					EnumValues:  []string{"safe", "fast"},
					Description: "Selects the normalizer mode.",
				},
			},
		},
		"capabilities": map[string]any{
			"request_normalizer": true,
		},
	}
}

// handleNormalize echoes the payload back unchanged. Replace the body with
// the real transformation.
func handleNormalize(request []byte) ([]byte, error) {
	var req pluginapi.RequestTransformRequest
	if errUnmarshal := json.Unmarshal(request, &req); errUnmarshal != nil {
		return errorEnvelope("invalid_request", "malformed request envelope", 400), nil
	}
	return okEnvelope(pluginapi.PayloadResponse{Body: req.Body})
}

func okEnvelope(v any) ([]byte, error) {
	raw, errMarshal := json.Marshal(v)
	if errMarshal != nil {
		return nil, errMarshal
	}
	return json.Marshal(envelope{OK: true, Result: raw})
}

// errorEnvelope mirrors pluginabi.NewErrorEnvelope but is callable from paths
// that cannot return an error. Always pass an httpStatus: omitting it makes
// CPA downgrade the failure to HTTP 500 and clients will back off and retry.
func errorEnvelope(code, message string, httpStatus int) []byte {
	raw, _ := json.Marshal(envelope{
		OK:    false,
		Error: pluginabi.NewError(code, message, httpStatus),
	})
	return raw
}

func writeResponse(response *C.cliproxy_buffer, raw []byte) {
	if response == nil || len(raw) == 0 {
		return
	}
	ptr := C.CBytes(raw)
	if ptr == nil {
		return
	}
	response.ptr = ptr
	response.len = C.size_t(len(raw))
}
