using StaticArrays: SVector

"""
    SymmetricInjectionCylinder <: AbstractInjectionShape

Represents a cylindrical volume used for particle injection, symmetric along its axis.

Particles are typically sampled within this volume, and their trajectories are adjusted
to pass through it.

# Fields
- `r_injection::Float64`: The radius of the injection cylinder.
- `l_endcap::Float64`: The length of the endcap regions of the cylinder.
"""
struct SymmetricInjectionCylinder <: AbstractInjectionShape
    r_injection::Float64
    l_endcap::Float64
end

"""
    Base.show(io::IO, cylinder::SymmetricInjectionCylinder)

Prints a formatted string representation of a `SymmetricInjectionCylinder` object.

# Arguments
- `io::IO`: The I/O stream to write to.
- `cylinder::SymmetricInjectionCylinder`: The cylinder object to display.
"""
function Base.show(io::IO, cylinder::SymmetricInjectionCylinder)
    print(
        io,
        """
        r_injection (m): $(cylinder.r_injection / units.m)
        l_endcap (m): $(cylinder.l_endcap / units.m)
        """
    )
end

"""
    AsymmetricInjectionCylinder <: AbstractInjectionShape

Represents a cylindrical volume for particle injection with potentially different
incoming and outgoing endcap lengths.

# Fields
- `r_injection::Float64`: The radius of the injection cylinder.
- `l_incoming_endcap::Float64`: The length of the incoming endcap region of the cylinder.
- `l_outgoing_endcap::Float64`: The length of the outgoing endcap region of the cylinder.
"""
struct AsymmetricInjectionCylinder <: AbstractInjectionShape
    r_injection::Float64
    l_incoming_endcap::Float64
    l_outgoing_endcap::Float64
end

"""
    Base.show(io::IO, cylinder::AsymmetricInjectionCylinder)

Prints a formatted string representation of an `AsymmetricInjectionCylinder` object.

# Arguments
- `io::IO`: The I/O stream to write to.
- `cylinder::AsymmetricInjectionCylinder`: The cylinder object to display.
"""
function Base.show(io::IO, cylinder::AsymmetricInjectionCylinder)
    print(
        io,
        """
        r_injection (m): $(cylinder.r_injection / units.m)
        l_incoming_endcap (m): $(cylinder.l_incoming_endcap / units.m)
        l_outgoing_endcap (m): $(cylinder.l_outgoing_endcap / units.m)
        """
    )
end

"""
    Base.rand(cylinder::SymmetricInjectionCylinder)

Sample an point of closest approach uniformly on a circle lying
in the xy-plane

# Example
```julia-repl
julia> injector = SymmetricInjectionCylinder(900units.m, 1units.km);
julia> rand.seed!(0);
julia> rand(injector)
TBW
```
"""
function Base.rand(cylinder::SymmetricInjectionCylinder)
    b = cylinder.r_injection .* sqrt(rand())
    ψ = rand(Uniform(0, 2π))
    p = SVector{3}([b * cos(ψ), b * sin(ψ), 0])
    return p
end

"""
    Base.rand(cylinder::AsymmetricInjectionCylinder)

Sample an point of closest approach uniformly on a circle of
radius r = cylinder.r_injection lying in the xy-plane. This can then
be rotated to a plane perpendicular to a particle's direction to
give the point of closest approach

# Example
```julia-repl
julia> injector = AsymmetricInjectionCylinder(900units.m, 1units.km);
julia> rand.seed!(0);
julia> rand(injector)
TBW
```
"""
function Base.rand(cylinder::AsymmetricInjectionCylinder)
    b = cylinder.r_injection .* sqrt(rand())
    ψ = rand(Uniform(0, 2π))
    p = SVector{3}([b * cos(ψ), b * sin(ψ), 0])
    return p
end

"""
    impact_parameter(p::SVector{3}, d::SVector{3}) -> Float64

Calculates the impact parameter for a point `p` relative to a line defined by a direction `d` passing through the origin.

# Arguments
- `p::SVector{3}`: The position vector of the point.
- `d::SVector{3}`: The direction vector of the line (assumed to be normalized or will be normalized implicitly by dot product logic).

# Returns
- `Float64`: The calculated impact parameter.
"""
function impact_parameter(p, d)
    r = norm(p)
    return r * sqrt(1 - (sum(p .* d) / r)^2)
end

"""
    impact_parameter(event) -> Float64

Calculates the impact parameter for an event based on its entry state.

This is a convenience method that extracts the position and direction from the
`event`'s `entry_state` and then calls the primary `impact_parameter` function.

# Arguments
- `event`: An event object (e.g., `InjectionEvent`) that has an `entry_state` field,
  which in turn has `position` (a `Coordinate`) and `direction` (a `Direction`) fields.

# Returns
- `Float64`: The calculated impact parameter.
"""
function impact_parameter(event)
    p = event.entry_state.position
    d = event.entry_state.direction.proj
    return impact_parameter(p, d)
end

"""
    probability(cylinder::SymmetricInjectionCylinder) -> Float64

Calculates the probability density for sampling a point within the injection cylinder's cross-sectional area.

This is the inverse of the area of the cylinder's base.

# Arguments
- `cylinder::SymmetricInjectionCylinder`: The injection cylinder object.

# Returns
- `Float64`: The probability density.
"""
function probability(cylinder::SymmetricInjectionCylinder)
    return 1 / (π * cylinder.r_injection^2)
end

"""
    probability(cylinder::SymmetricInjectionCylinder, event) -> Float64

Calculates the probability density for a given event occurring within a symmetric injection cylinder.

This function asserts that the event's impact parameter is within the cylinder's radius
and returns the inverse of the cylinder's base area as the probability density.

# Arguments
- `cylinder::SymmetricInjectionCylinder`: The injection cylinder object.
- `event`: An event object (e.g., `InjectionEvent`) used to calculate the impact parameter.

# Returns
- `Float64`: The probability density.
"""
function probability(cylinder::SymmetricInjectionCylinder, event)
    
    b = impact_parameter(event)
    @assert b <= cylinder.r_injection
   
    return 1 / (π * cylinder.r_injection^2)
end
