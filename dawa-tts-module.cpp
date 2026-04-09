// dawa-tts-module.cpp --- Emacs dynamic module for Supertonic TTS -*- C++ -*-

// Copyright (C) 2025 Sangjee Dondrub

// This file provides Emacs Lisp bindings for the Supertonic TTS engine using
// ONNX Runtime for fast, on-device text-to-speech synthesis.

#include <emacs-module.h>
#include "lib/supertonic.h"
#include <string>
#include <memory>
#include <sstream>
#include <filesystem>
#include <ctime>

// -----------------------------------------------------------------------------
// GPL Compatibility
// -----------------------------------------------------------------------------

int plugin_is_GPL_compatible;

// -----------------------------------------------------------------------------
// Global State
// -----------------------------------------------------------------------------

namespace {
    // ONNX Runtime environment (initialized once)
    std::unique_ptr<Ort::Env> g_ort_env;

    // TTS engine instance
    std::unique_ptr<TextToSpeech> g_tts;

    // Current loaded voice style
    std::unique_ptr<Style> g_current_style;

    // Memory info for tensor operations
    std::unique_ptr<Ort::MemoryInfo> g_memory_info;

    // Assets directory paths
    std::string g_onnx_dir;
    std::string g_voice_dir;

    // Initialization flag
    bool g_initialized = false;
}

// -----------------------------------------------------------------------------
// Helper Functions
// -----------------------------------------------------------------------------

// Extract string from emacs_value
static std::string extract_string(emacs_env *env, emacs_value arg) {
    ptrdiff_t size = 0;
    env->copy_string_contents(env, arg, nullptr, &size);

    std::string result(size - 1, '\0');  // -1 for null terminator
    env->copy_string_contents(env, arg, &result[0], &size);

    return result;
}

// Create emacs string from C++ string
static emacs_value make_string(emacs_env *env, const std::string& str) {
    return env->make_string(env, str.c_str(), str.length());
}

// Signal error to Emacs
static void signal_error(emacs_env *env, const char *message) {
    emacs_value error_symbol = env->intern(env, "error");
    emacs_value error_message = env->make_string(env, message, strlen(message));
    env->non_local_exit_signal(env, error_symbol, error_message);
}

// Generate unique temp file path
static std::string generate_temp_wav_path() {
    std::time_t now = std::time(nullptr);
    std::ostringstream oss;
    oss << "/tmp/dawa-tts-" << now << ".wav";
    return oss.str();
}

// -----------------------------------------------------------------------------
// Emacs Functions
// -----------------------------------------------------------------------------

// (dawa-tts-module-init ONNX-DIR) -> t or nil
static emacs_value
Fdawa_tts_module_init(emacs_env *env, ptrdiff_t nargs, emacs_value args[], void *data) noexcept {
    (void)nargs;
    (void)data;

    try {
        // Extract ONNX directory path
        g_onnx_dir = extract_string(env, args[0]);

        // Verify directory exists
        if (!std::filesystem::exists(g_onnx_dir)) {
            signal_error(env, ("ONNX directory does not exist: " + g_onnx_dir).c_str());
            return env->intern(env, "nil");
        }

        // Initialize ONNX Runtime environment
        g_ort_env = std::make_unique<Ort::Env>(ORT_LOGGING_LEVEL_WARNING, "dawa-tts");

        // Create memory info
        g_memory_info = std::make_unique<Ort::MemoryInfo>(
            Ort::MemoryInfo::CreateCpu(OrtArenaAllocator, OrtMemTypeDefault)
        );

        // Load TTS models
        g_tts = loadTextToSpeech(*g_ort_env, g_onnx_dir, false);  // false = CPU mode

        g_initialized = true;

        return env->intern(env, "t");

    } catch (const std::exception& e) {
        signal_error(env, ("TTS initialization failed: " + std::string(e.what())).c_str());
        return env->intern(env, "nil");
    }
}

// (dawa-tts-module-load-voice VOICE-PATH) -> t or nil
static emacs_value
Fdawa_tts_module_load_voice(emacs_env *env, ptrdiff_t nargs, emacs_value args[], void *data) noexcept {
    (void)nargs;
    (void)data;

    if (!g_initialized) {
        signal_error(env, "TTS not initialized. Call dawa-tts-module-init first.");
        return env->intern(env, "nil");
    }

    try {
        std::string voice_path = extract_string(env, args[0]);

        // Verify voice file exists
        if (!std::filesystem::exists(voice_path)) {
            signal_error(env, ("Voice file does not exist: " + voice_path).c_str());
            return env->intern(env, "nil");
        }

        // Load voice style
        g_current_style = std::make_unique<Style>(loadVoiceStyle({voice_path}, true));  // true = verbose

        return env->intern(env, "t");

    } catch (const std::exception& e) {
        signal_error(env, ("Voice loading failed: " + std::string(e.what())).c_str());
        return env->intern(env, "nil");
    }
}

// (dawa-tts-module-synthesize TEXT STEPS SPEED OUTPUT-PATH) -> path-string or nil
// OUTPUT-PATH can be nil for auto-generated path
static emacs_value
Fdawa_tts_module_synthesize(emacs_env *env, ptrdiff_t nargs, emacs_value args[], void *data) noexcept {
    (void)nargs;
    (void)data;

    if (!g_initialized) {
        signal_error(env, "TTS not initialized. Call dawa-tts-module-init first.");
        return env->intern(env, "nil");
    }

    if (!g_current_style) {
        signal_error(env, "No voice loaded. Call dawa-tts-module-load-voice first.");
        return env->intern(env, "nil");
    }

    try {
        // Extract arguments
        std::string text = extract_string(env, args[0]);
        int steps = env->extract_integer(env, args[1]);
        double speed = env->extract_float(env, args[2]);

        // Determine output path
        std::string output_path;
        if (env->is_not_nil(env, args[3])) {
            output_path = extract_string(env, args[3]);
        } else {
            output_path = generate_temp_wav_path();
        }

        // Validate parameters
        if (text.empty()) {
            signal_error(env, "Text cannot be empty");
            return env->intern(env, "nil");
        }

        if (steps < 1 || steps > 10) {
            signal_error(env, "Steps must be between 1 and 10");
            return env->intern(env, "nil");
        }

        if (speed < 0.5 || speed > 2.0) {
            signal_error(env, "Speed must be between 0.5 and 2.0");
            return env->intern(env, "nil");
        }

        // Synthesize speech
        auto result = g_tts->call(*g_memory_info, text, *g_current_style, steps,
                                   static_cast<float>(speed), 0.3f);

        // Write WAV file
        int sample_rate = g_tts->getSampleRate();
        writeWavFile(output_path, result.wav, sample_rate);

        // Clear tensor buffers to free memory
        clearTensorBuffers();

        // Return output path
        return make_string(env, output_path);

    } catch (const std::exception& e) {
        signal_error(env, ("Speech synthesis failed: " + std::string(e.what())).c_str());
        return env->intern(env, "nil");
    }
}

// (dawa-tts-module-list-voices VOICE-DIR) -> (list "M1" "M2" ... "F5")
static emacs_value
Fdawa_tts_module_list_voices(emacs_env *env, ptrdiff_t nargs, emacs_value args[], void *data) noexcept {
    (void)nargs;
    (void)data;

    try {
        std::string voice_dir = extract_string(env, args[0]);

        if (!std::filesystem::exists(voice_dir)) {
            signal_error(env, ("Voice directory does not exist: " + voice_dir).c_str());
            return env->intern(env, "nil");
        }

        // Scan for .json files
        std::vector<std::string> voices;
        for (const auto& entry : std::filesystem::directory_iterator(voice_dir)) {
            if (entry.path().extension() == ".json") {
                std::string voice_name = entry.path().stem().string();
                voices.push_back(voice_name);
            }
        }

        // Build Emacs list
        emacs_value list_symbol = env->intern(env, "list");
        std::vector<emacs_value> voice_values;

        for (const auto& voice : voices) {
            voice_values.push_back(make_string(env, voice));
        }

        return env->funcall(env, list_symbol, voice_values.size(), voice_values.data());

    } catch (const std::exception& e) {
        signal_error(env, ("Failed to list voices: " + std::string(e.what())).c_str());
        return env->intern(env, "nil");
    }
}

// (dawa-tts-module-cleanup) -> t
static emacs_value
Fdawa_tts_module_cleanup(emacs_env *env, ptrdiff_t nargs, emacs_value args[], void *data) noexcept {
    (void)nargs;
    (void)args;
    (void)data;

    try {
        // Clean up in reverse order
        g_current_style.reset();
        g_tts.reset();
        g_memory_info.reset();
        g_ort_env.reset();

        clearTensorBuffers();

        g_initialized = false;

        return env->intern(env, "t");

    } catch (const std::exception& e) {
        signal_error(env, ("Cleanup failed: " + std::string(e.what())).c_str());
        return env->intern(env, "nil");
    }
}

// -----------------------------------------------------------------------------
// Module Initialization
// -----------------------------------------------------------------------------

int emacs_module_init(struct emacs_runtime *ert) noexcept {
    emacs_env *env = ert->get_environment(ert);

    // Helper lambda for registering functions
    auto defun = [env](const char *name, ptrdiff_t min_arity, ptrdiff_t max_arity,
                       emacs_value (*function)(emacs_env*, ptrdiff_t, emacs_value*, void*) noexcept,
                       const char *doc) {
        emacs_value func_symbol = env->intern(env, name);
        emacs_value func_impl = env->make_function(env, min_arity, max_arity, function, doc, nullptr);

        emacs_value fset = env->intern(env, "fset");
        emacs_value fset_args[] = {func_symbol, func_impl};
        env->funcall(env, fset, 2, fset_args);
    };

    // Register functions
    defun("dawa-tts-module-init", 1, 1, Fdawa_tts_module_init,
          "Initialize the TTS engine with ONNX-DIR containing model files.");

    defun("dawa-tts-module-load-voice", 1, 1, Fdawa_tts_module_load_voice,
          "Load voice style from VOICE-PATH (JSON file).");

    defun("dawa-tts-module-synthesize", 4, 4, Fdawa_tts_module_synthesize,
          "Synthesize TEXT to speech with STEPS inference steps, SPEED multiplier,\n\
and save to OUTPUT-PATH. Returns path to generated WAV file.");

    defun("dawa-tts-module-list-voices", 1, 1, Fdawa_tts_module_list_voices,
          "List available voice styles in VOICE-DIR.");

    defun("dawa-tts-module-cleanup", 0, 0, Fdawa_tts_module_cleanup,
          "Clean up TTS resources.");

    // Provide feature
    emacs_value provide = env->intern(env, "provide");
    emacs_value feature = env->intern(env, "dawa-tts-module");
    emacs_value provide_args[] = {feature};
    env->funcall(env, provide, 1, provide_args);

    return 0;
}
