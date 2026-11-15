#include "Film.h"
#include <math.h>
#include <stdlib.h>
#include <string.h>

const FilmStock kFilmStocks[] = {
    {"SILVER",        0.45f, 0.02f, 0.98f, 1.00f, 1.0f},   // default: medium contrast
    {"ASH",           0.10f, 0.10f, 0.92f, 0.95f, 0.8f},   // faded: lifted blacks, softer whites
    {"HIGH CONTRAST", 1.00f, 0.00f, 1.00f, 1.12f, 1.3f},
};
const int kFilmStockCount = sizeof kFilmStocks / sizeof kFilmStocks[0];

void FilmToneCurve(const FilmStock *f, uint8_t curve[256]) {
    for (int i = 0; i < 256; i++) {
        float x = i / 255.0f;
        x = powf(x, f->gamma);
        float s = x * x * (3.0f - 2.0f * x);            // smoothstep S-curve
        x = x + (s - x) * f->contrast;
        x = f->black + x * (f->white - f->black);
        int v = (int)lrintf(x * 255.0f);
        curve[i] = v < 0 ? 0 : v > 255 ? 255 : v;
    }
}

void FilmPreviewTable(const FilmStock *f, uint32_t table[256]) {
    uint8_t c[256];
    FilmToneCurve(f, c);
    for (int i = 0; i < 256; i++) table[i] = 0xff000000u | (uint32_t)c[i] * 0x010101u;
}

// Grain: a 256x256 tile of blurred gaussian-ish noise (std about 32), sampled at
// two scales with random offsets so the tile doesn't repeat visibly.
#define TILE 256
static int8_t gTile[TILE * TILE];

static uint32_t xorshift(uint32_t *s) { uint32_t x = *s; x ^= x << 13; x ^= x >> 17; x ^= x << 5; return *s = x; }

static void makeTile(void) {
    static int made;
    if (made) return;
    int16_t *raw = malloc(TILE * TILE * sizeof *raw);
    uint32_t s = 0x9e3779b9u;
    for (int i = 0; i < TILE * TILE; i++) {
        int sum = 0;
        for (int k = 0; k < 4; k++) sum += (int)(xorshift(&s) & 0xff);
        raw[i] = sum - 510;                               // std about 148
    }
    for (int y = 0; y < TILE; y++)
        for (int x = 0; x < TILE; x++) {                  // 3x3 blur: clumped grain
            int sum = 0;
            for (int dy = -1; dy <= 1; dy++)
                for (int dx = -1; dx <= 1; dx++)
                    sum += raw[((y + dy) & (TILE - 1)) * TILE + ((x + dx) & (TILE - 1))] * ((dx == 0) + 1) * ((dy == 0) + 1);
            int v = sum / 16 * 32 / 74;                    // blurred std about 74 -> 32
            gTile[y * TILE + x] = v < -127 ? -127 : v > 127 ? 127 : v;
        }
    free(raw);
    made = 1;
}

void FilmDevelop(const FilmStock *f, uint8_t *pixels, int width, int height, int rowBytes, uint32_t seed) {
    makeTile();
    uint8_t curve[256];
    int16_t amp[256];                                     // grain amplitude by tone, Q7
    FilmToneCurve(f, curve);
    for (int i = 0; i < 256; i++) {
        float t = i / 255.0f;
        float a = f->grain * (0.35f + 0.65f * 4.0f * t * (1.0f - t));   // strongest in midtones
        amp[i] = (int16_t)lrintf(a * 0.5f * 128.0f);
    }
    uint32_t s = seed | 1;
    int ox1 = xorshift(&s) & (TILE - 1), oy1 = xorshift(&s) & (TILE - 1);
    int ox2 = xorshift(&s) & (TILE - 1), oy2 = xorshift(&s) & (TILE - 1);
    for (int y = 0; y < height; y++) {
        uint8_t *row = pixels + y * rowBytes;
        const int8_t *fine = gTile + ((y + oy1) & (TILE - 1)) * TILE;
        const int8_t *coarse = gTile + (((y >> 1) + oy2) & (TILE - 1)) * TILE;
        for (int x = 0; x < width; x++) {
            int v = curve[row[x]];
            int n = fine[(x + ox1) & (TILE - 1)] * 3 + coarse[((x >> 1) + ox2) & (TILE - 1)];
            v += (n * amp[v]) >> 9;
            row[x] = v < 0 ? 0 : v > 255 ? 255 : v;
        }
    }
}
