# Repository Cleanup Notes

## Largest Git-Tracked Files

| File | Size | Assessment |
|---|---|---|
| `resources/splines/perfect_valley/perfect_valley_spline.jld2` | 8.8MB | Questionable — splines are derived/generated data. If regenerable from source, should not be in git. |
| `resources/basic_geometry.h5.back` | 6.2MB | Should be deleted — `.back` files are backup artifacts, not source. |
| `resources/basic_geometry.h5` | 6.2MB | Reasonable to keep if it is the canonical geometry input and not easily regenerated. |
| `resources/cross_section_tables/cross_sections.h5` | 2.1MB | Likely necessary if these are precomputed tables used at runtime. |
| `notebooks/science_paper_figures.ipynb` | 1.7MB | Large because Jupyter notebooks embed output cells. Should strip output before committing. |
| `test/resources/example_corsika.parquet` | 452KB | Necessary for tests. |
| `resources/ColcaValleyData.txt` | 364KB | Likely necessary as source topographic data. |
| `notebooks/create_geometry/triangulate_sphere.ipynb` | 25KB | Embedded notebook output — strip before committing. |

## Recommendations

1. **Delete `resources/basic_geometry.h5.back`** — 6.2MB backup artifact with no source value.
2. **Evaluate `perfect_valley_spline.jld2`** — if a script generates it, remove from git and generate on demand. Consider Git LFS if it must stay.
3. **Strip notebook outputs** before committing. Use `nbstripout` as a pre-commit hook to prevent future bloat.
4. **Consider Git LFS** for `.h5` and `.jld2` files if they need to remain in the repository.
