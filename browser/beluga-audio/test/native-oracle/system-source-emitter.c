// Explicit test helper only: bounded stereo output on the existing default device.
// No capture, device selection, format/volume writes, driver or permission requests.
#include <AudioToolbox/AudioToolbox.h>
#include <CoreAudio/CoreAudio.h>
#include <CoreFoundation/CoreFoundation.h>
#include <math.h>
#include <poll.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

typedef struct {
    AudioQueueRef queue;
    atomic_bool running;
    atomic_uint_fast64_t frames;
    atomic_int error;
    uint64_t sample;
    double leftHz, rightHz;
} Emitter;

static double monotonic(void) {
    struct timespec value;
    if (clock_gettime(CLOCK_MONOTONIC, &value) != 0) return -1;
    return value.tv_sec + value.tv_nsec / 1e9;
}

static bool default_output_matches(const char *expected) {
    AudioObjectPropertyAddress address = { kAudioHardwarePropertyDefaultOutputDevice,
        kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain };
    AudioObjectID device = kAudioObjectUnknown;
    UInt32 size = sizeof(device);
    if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &address, 0, NULL, &size, &device) != noErr ||
        size != sizeof(device) || device == kAudioObjectUnknown) return false;
    address.mSelector = kAudioDevicePropertyDeviceUID;
    CFStringRef uid = NULL;
    size = sizeof(uid);
    char bytes[1024];
    const OSStatus status = AudioObjectGetPropertyData(device, &address, 0, NULL, &size, &uid);
    const bool matches = status == noErr && size == sizeof(uid) && uid &&
        CFStringGetCString(uid, bytes, sizeof(bytes), kCFStringEncodingUTF8) && strcmp(bytes, expected) == 0;
    if (status == noErr && uid) CFRelease(uid);
    return matches;
}

static void fill(Emitter *emitter, AudioQueueBufferRef buffer) {
    float *samples = (float *)buffer->mAudioData;
    for (unsigned frame = 0; frame < 480; frame++, emitter->sample++) {
        const double time = emitter->sample / 48000.0;
        samples[frame * 2] = (float)(0.12 * sin(2.0 * M_PI * emitter->leftHz * time));
        samples[frame * 2 + 1] = (float)(0.12 * sin(2.0 * M_PI * emitter->rightHz * time));
    }
    buffer->mAudioDataByteSize = 480 * 2 * sizeof(float);
}

static void callback(void *context, AudioQueueRef queue, AudioQueueBufferRef buffer) {
    Emitter *emitter = context;
    if (!atomic_load_explicit(&emitter->running, memory_order_acquire)) return;
    atomic_fetch_add_explicit(&emitter->frames, 480, memory_order_relaxed);
    fill(emitter, buffer);
    OSStatus status = AudioQueueEnqueueBuffer(queue, buffer, 0, NULL);
    if (status != noErr) atomic_store_explicit(&emitter->error, status, memory_order_release);
}

static bool stop(Emitter *emitter) {
    atomic_store_explicit(&emitter->running, false, memory_order_release);
    if (!emitter->queue) return true;
    const OSStatus stopped = AudioQueueStop(emitter->queue, true);
    const OSStatus disposed = AudioQueueDispose(emitter->queue, true);
    if (disposed == noErr) emitter->queue = NULL;
    return stopped == noErr && disposed == noErr;
}

static bool start(Emitter *emitter, const char *outputUID) {
    if (emitter->queue || !default_output_matches(outputUID)) return false;
    AudioStreamBasicDescription format = { .mSampleRate = 48000,
        .mFormatID = kAudioFormatLinearPCM, .mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
        .mBytesPerPacket = 8, .mFramesPerPacket = 1, .mBytesPerFrame = 8,
        .mChannelsPerFrame = 2, .mBitsPerChannel = 32 };
    if (AudioQueueNewOutput(&format, callback, emitter, NULL, NULL, 0, &emitter->queue) != noErr) return false;
    emitter->sample = 0;
    for (unsigned index = 0; index < 3; index++) {
        AudioQueueBufferRef buffer = NULL;
        if (AudioQueueAllocateBuffer(emitter->queue, 480 * 8, &buffer) != noErr || !buffer) return false;
        fill(emitter, buffer);
        if (AudioQueueEnqueueBuffer(emitter->queue, buffer, 0, NULL) != noErr) return false;
    }
    atomic_store_explicit(&emitter->running, true, memory_order_release);
    if (AudioQueueStart(emitter->queue, NULL) != noErr || !default_output_matches(outputUID)) return false;
    return true;
}

static bool integer(const char *text, int low, int high, int *result) {
    char *end = NULL;
    if (!text || !*text) return false;
    const long value = strtol(text, &end, 10);
    if (!end || *end || value < low || value > high) return false;
    *result = (int)value;
    return true;
}

int main(int argc, char **argv) {
    int seconds = 0, left = 0, right = 0;
    if (argc != 5 || !integer(argv[1], 45, 90, &seconds) || !integer(argv[2], 200, 4000, &left) ||
        !integer(argv[3], 200, 4000, &right) || left == right || !*argv[4] || strlen(argv[4]) > 256) return 64;
    setvbuf(stdout, NULL, _IOLBF, 0);
    Emitter emitter = { .queue = NULL, .leftHz = left, .rightHz = right };
    atomic_init(&emitter.running, false); atomic_init(&emitter.frames, 0); atomic_init(&emitter.error, 0);
    const double begun = monotonic(), deadline = begun + seconds;
    if (begun < 0 || !default_output_matches(argv[4])) return 65;
    unsigned starts = 0, stops = 0;
    bool success = false, failed = false;
    char command[16]; size_t count = 0;
    puts("{\"event\":\"ready\"}");
    while (!failed && monotonic() >= 0 && monotonic() < deadline) {
        struct pollfd input = { .fd = STDIN_FILENO, .events = POLLIN };
        const int polled = poll(&input, 1, 100);
        if (polled < 0 || atomic_load_explicit(&emitter.error, memory_order_acquire) != 0) break;
        if (polled == 0) continue;
        if (!(input.revents & POLLIN)) break;
        char byte;
        if (read(STDIN_FILENO, &byte, 1) != 1) break;
        if (byte != '\n') {
            if (count >= sizeof(command) - 1 || byte < 'A' || byte > 'Z') break;
            command[count++] = byte; continue;
        }
        command[count] = '\0'; count = 0;
        if (strcmp(command, "START") == 0) {
            if (starts >= 3 || starts != stops || !start(&emitter, argv[4])) { failed = true; break; }
            starts++; printf("{\"event\":\"started\",\"starts\":%u}\n", starts);
        } else if (strcmp(command, "STOP") == 0) {
            if (starts != stops + 1 || !stop(&emitter)) { failed = true; break; }
            stops++; printf("{\"event\":\"stopped\",\"stops\":%u}\n", stops);
        } else if (strcmp(command, "QUIT") == 0) {
            success = starts == stops && starts > 0; break;
        } else break;
    }
    const bool clean = stop(&emitter);
    success = success && clean && !failed && default_output_matches(argv[4]) &&
        atomic_load_explicit(&emitter.error, memory_order_acquire) == 0;
    printf("{\"event\":\"complete\",\"starts\":%u,\"stops\":%u,\"frames\":%llu,\"teardown\":%s}\n",
        starts, stops, (unsigned long long)atomic_load_explicit(&emitter.frames, memory_order_acquire),
        success ? "true" : "false");
    return success ? 0 : 1;
}
