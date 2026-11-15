#include <stdint.h>

typedef struct {
    const char *name;
    float contrast;   // S-curve strength, 0 = linear
    float black;      // output level for input black, 0..1 (lifted blacks)
    float white;
    float gamma;      // midtone gamma, < 1 brightens
    float grain;
    float fade;       // faded-film floor: shadows flatten into this gray (0 = none)
} FilmStock;

extern const FilmStock kFilmStocks[];
extern const int kFilmStockCount;

void FilmToneCurve(const FilmStock *f, uint8_t curve[256]);
// The curve as gray BGRA words, gray_bgra's table.
void FilmPreviewTable(const FilmStock *f, uint32_t table[256]);
void FilmDevelop(const FilmStock *f, uint8_t *pixels, int width, int height, int rowBytes, uint32_t seed);
