"""
    CorsikaEvent{T<:Real}

Represents a particle event from a CORSIKA simulation.

# Fields
- `particle::Particle{T}`: The `Particle` object representing the event.
- `weight::T`: The statistical weight of the particle.
"""
struct CorsikaEvent{T<:Real}
    particle::Particle{T}
    weight::T
end

"""
    read_corsika(
        basedir::String,
        cs_earth::CoordinateSystem{T};
        t0=0.0u"s",
        filter_fxn::Function=x->true
    ) where {T<:Real}

Reads CORSIKA simulation data from a directory structure and provides an iterator over the events.

This function scans a base directory for subdirectories matching "shower_*/particles/",
reads the `config.yaml` and `particles.parquet` files within each, and sets up a
`MultiParquetIterator` to stream `CorsikaEvent` objects.

# Arguments
- `basedir::String`: The base directory containing the CORSIKA shower data.
- `cs_earth::CoordinateSystem{T}`: The Earth-centered coordinate system to which the event coordinates will be transformed.
- `t0`: Optional time offset to add to CORSIKA hit times. Defaults to `0.0u"s"`.
- `filter_fxn::Function`: An optional function to filter events. It should take a `CorsikaEvent` and return `true` to keep it.

# Returns
- A `MultiParquetIterator` that yields `CorsikaEvent` objects.
"""
function read_corsika(
    basedir::String,
    cs_earth::CoordinateSystem{T};
    t0=0.0u"s",
    filter_fxn::Function=x->true
) where {T<:Real}
    dirs = glob("shower_*/particles/", basedir)
    filenames, transforms = String[], Function[]

    for dir in dirs
        if ~isfile("$(dir)/summary.yaml")
            @warn "$(dir) did not finish running."
            continue
        end
        config_file = "$(dir)/config.yaml"
        particles_file = "$(dir)/particles.parquet"

        config = open(config_file) do file
            YAML.load(file)
        end
    
        r = AngleAxis(-π/2, cs_earth.origin...)
        cs_corsika = CoordinateSystem(
            cs_earth.origin,
            Float64.(cs_earth.rotation*r)
        )
    
        rot = RotMatrix(SMatrix{3, 3, T, 9}([
            config["x-axis"]...;
            config["y-axis"]...;
            config["plane"]["normal"]
        ]))
        center = config["plane"]["center"] .* u"m"
        trans(row) = CorsikaEvent(row, rot, center, cs_corsika, cs_earth; t0=t0)
        push!(filenames, particles_file)
        push!(transforms, trans)
    end
    return MultiParquetIterator(filenames, transforms[1]; T=CorsikaEvent)
end

"""
    CorsikaEvent(
        row,
        rot::V,
        center,
        cs_corsika::CoordinateSystem{U},
        cs_earth::CoordinateSystem{U};
        t0=0.0u"s"
    ) where {U<:Real, V<:Rotation}

Constructs a `CorsikaEvent` from a row of a Parquet file and associated coordinate transformation data.

This function is typically used as a transformation function by `MultiParquetIterator` within `read_corsika`.
It reads particle properties from the table row, applies the necessary rotations and translations
to convert from CORSIKA's coordinate system to the Earth-centered one, and returns a `CorsikaEvent`.

# Arguments
- `row`: A row from a Parquet table containing particle data (pdg, energy, position, direction, etc.).
- `rot::V`: A `Rotation` matrix to transform from the shower plane to the CORSIKA coordinate system.
- `center`: The center of the shower plane.
- `cs_corsika::CoordinateSystem{U}`: The CORSIKA coordinate system.
- `cs_earth::CoordinateSystem{U}`: The target Earth-centered coordinate system.
- `t0`: Optional time offset to add to the CORSIKA hit time. Defaults to `0.0u"s"`.

# Returns
- A `CorsikaEvent` object containing a `Particle` with the CORSIKA hit time added to `t0`.
"""
function CorsikaEvent(
    row,
    rot::V,
    center,
    cs_corsika::CoordinateSystem{U},
    cs_earth::CoordinateSystem{U};
    t0=0.0u"s"
) where {U<:Real, V<:Rotation}
    d = Direction(rot * [row.nx, row.ny, row.nz], cs_corsika)
    p = Coordinate((rot * [row.x, row.y, row.z] .* u"m" .+ center)  .- [0.0u"km", 0.0u"km", 6371.0u"km"], cs_corsika)
    e = U(row.kinetic_energy * u"GeV")
    pdg = ParticleType(Int64(row.pdg))
    particle = Particle(pdg, e, convert(cs_earth, p), convert(cs_earth, d), t0 + row.time*u"s")
    return CorsikaEvent(particle, Float64(row.weight))
end
