// Film stocks: a tone curve for the live view and the photo, plus grain for the photo.
#include <stdint.h>

typedef struct {
    const char *name;
    float contrast;   // S-curve strength, 0 = linear
    float black;      // output level for input black, 0..1 (lifted blacks)
    float white;      // output level for input white
    float gamma;      // midtone gamma, < 1 brightens
    float grain;      // grain strength, 1 = normal
} FilmStock;

extern const FilmStock kFilmStocks[];
extern const int kFilmStockCount;

// 256-entry tone curve as 8-bit values.
void FilmToneCurve(const FilmStock *f, uint8_t curve[256]);
// The same curve as opaque gray BGRA words, for the live view (gray_bgra's table).
void FilmPreviewTable(const FilmStock *f, uint32_t table[256]);
// Apply tone curve and grain to an 8-bit gray image in place. seed varies the grain.
void FilmDevelop(const FilmStock *f, uint8_t *pixels, int width, int height, int rowBytes, uint32_t seed);
