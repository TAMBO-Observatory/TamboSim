using Makie
using CairoMakie
using LaTeXStrings

res_string = L"t_{\mathrm{res}} = t_{\mathrm{hit}} - t_{\mathrm{exp}}"
nhit_string = L"N_{\mathrm{hit}}"
tot_string = "ToT"

cs1 = [
    colorant"#29a2c6",
    colorant"#ff6d31",
    colorant"#ef597b",
    colorant"#9467bd",
    colorant"#73b66b",
    colorant"#ffcb18",
]

my_theme = Theme(
    fontsize=20,
    palette = (color = Makie.wong_colors(), linestyle = [:solid]),
    Lines = (cycle = Cycle([:color]),),
    Stairs = (cycle = Cycle([:color]),),
    Axis = (
            xgridvisible = false,
            ygridvisible = false,
        ),

)
set_theme!(merge(my_theme, theme_latexfonts()))


