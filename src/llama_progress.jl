# Llama-themed progress bar for TAMBO simulations
# Based on the TAMBO pixel art llama mascot

"""
    LLAMA_ASCII

ASCII art representation of the TAMBO llama mascot.
Based on the pixel art with brown body, red blanket, and yellow decoration.
"""
const LLAMA_ASCII = raw"""
        ██
       ████▌
       █  █▌
      ▄█▄▄█
  ▐▌ █▀██▀█
     █████
     █   █
     ▀   ▀
"""

const LLAMA_COMPACT = "▌█▀▄▌"

"""
    LlamaBarGlyphs

Custom bar glyphs featuring llama-themed progress.
"""
const LlamaBarGlyphs = BarGlyphs('▐', '█', '▓', '░', '▌')

"""
    llama_progress(n::Int; desc::String="", kwargs...)

Create a llama-themed Progress object for tracking simulation progress.

# Arguments
- `n::Int`: Total number of iterations
- `desc::String`: Description to show
- `kwargs...`: Additional arguments passed to Progress

# Example
```julia
p = llama_progress(100, desc="Injecting")
for i in 1:100
    # do work
    next!(p)
end
```
"""
function llama_progress(n::Int; desc::String="", kwargs...)
    llama_desc = isempty(desc) ? "🦙 Processing" : "🦙 $(desc)"
    return Progress(n;
        desc=llama_desc,
        barglyphs=LlamaBarGlyphs,
        barlen=40,
        color=:yellow,
        kwargs...
    )
end

"""
    @llama_showprogress(args...)

Macro wrapper around @showprogress with llama theming.
Displays a llama emoji and uses custom progress bar glyphs.

# Example
```julia
@llama_showprogress "Injecting" for frame in frames
    # process frame
end
```
"""
macro llama_showprogress(args...)
    if length(args) == 1
        loop = args[1]
        return quote
            ProgressMeter.@showprogress barglyphs=$LlamaBarGlyphs color=:yellow desc="🦙 " $loop
        end |> esc
    elseif length(args) == 2
        desc_expr = args[1]
        loop = args[2]
        return quote
            ProgressMeter.@showprogress barglyphs=$LlamaBarGlyphs color=:yellow desc="🦙 "*string($desc_expr)*" " $loop
        end |> esc
    else
        error("@llama_showprogress expects 1 or 2 arguments")
    end
end

"""
    print_llama()

Print the TAMBO llama mascot ASCII art to the terminal.
"""
function print_llama()
    # Colored version using ANSI codes
    brown = "\e[38;5;130m"
    dark_brown = "\e[38;5;52m"
    red = "\e[38;5;124m"
    yellow = "\e[38;5;226m"
    reset = "\e[0m"

    println("""
        $(dark_brown)██$(reset)
       $(brown)███$(dark_brown)█$(reset)$(brown)▌$(reset)
       $(brown)█$(dark_brown)  $(brown)█▌$(reset)
      $(brown)▄█$(dark_brown)▄▄$(brown)█$(reset)
  $(brown)▐▌$(reset) $(brown)█$(red)▀$(yellow)█$(red)▀$(brown)█$(reset)
     $(brown)█$(red)███$(brown)█$(reset)
     $(brown)█$(reset)   $(brown)█$(reset)
     $(dark_brown)▀$(reset)   $(dark_brown)▀$(reset)
    """)
end
