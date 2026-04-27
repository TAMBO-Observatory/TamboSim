struct InjectionPlane <: AbstractInjectionShape
    length::Float64
    width::Float64
    n̂::SVector{3, Float64}
    function InjectionPlane(length, width, n̂)
        n̂ /= norm(n̂)
        return new(length, width, n̂)
    end
end

function Base.rand(plane::InjectionPlane)
    x = rand(Uniform(-plane.length/2, plane.length/2))
    y = rand(Uniform(-plane.width/2, plane.width/2))
    a = SVector{3, Float64}(x, y, 0.0)
    θ = acos(plane.n̂.z)
    ϕ = atan(plane.n̂.y, plane.n̂.x)
    r = RotZ(ϕ) * RotY(θ)
    return r * a
end
