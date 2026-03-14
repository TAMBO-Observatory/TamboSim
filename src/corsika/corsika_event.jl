"""Mean Earth radius in kilometres, used for coordinate transformations."""
const EARTH_RADIUS = 6371.0u"km"

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
        # Precompute coordinate transform once per shower
        dr, co = precompute_cs_transform(cs_corsika, cs_earth)
        trans(row) = CorsikaEvent(row, rot, center, cs_earth, dr, co; t0=t0)
        push!(filenames, particles_file)
        push!(transforms, trans)
    end
    isempty(filenames) && throw(ArgumentError("No completed showers found in $basedir"))
    return MultiParquetIterator(filenames, transforms; T=CorsikaEvent)
end

"""
    precompute_cs_transform(cs_from::CoordinateSystem, cs_to::CoordinateSystem)

Precomputes the composed rotation and translation for converting coordinates
from `cs_from` to `cs_to`. Returns `(dir_rot, coord_rot, coord_offset)` where:
- `dir_rot`: rotation matrix for directions (rotation-only, no translation)
- `coord_rot`: same as `dir_rot` (used for coordinate rotation step)
- `coord_offset`: translation vector to apply before rotation

This avoids reconstructing `LinearMap`, `RotMatrix`, `Translation`, and their
inverses on every per-particle call to `convert`.
"""
function precompute_cs_transform(cs_from::CoordinateSystem, cs_to::CoordinateSystem)
    # Direction: r2 * inv(r1) * point
    r1_inv = SMatrix{3,3}(inv(RotMatrix(cs_from.rotation)))
    r2 = SMatrix{3,3}(RotMatrix(cs_to.rotation))
    dir_rot = r2 * r1_inv

    # Coordinate: r2 * (inv(t2)(t1(inv(r1)(point))))
    #           = r2 * (r1_inv * point + origin_from - origin_to)
    coord_offset = cs_from.origin - cs_to.origin

    return dir_rot, coord_offset
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

The particle speed is calculated from the kinetic energy and particle mass using relativistic kinematics
(γ = 1 + ke/(mc²), β = √(1 - 1/γ²), v = βc). If the particle mass is not in the lookup table,
the speed defaults to the speed of light.

# Arguments
- `row`: A row from a Parquet table containing particle data (pdg, energy, position, direction, etc.).
- `rot::V`: A `Rotation` matrix to transform from the shower plane to the CORSIKA coordinate system.
- `center`: The center of the shower plane.
- `cs_corsika::CoordinateSystem{U}`: The CORSIKA coordinate system.
- `cs_earth::CoordinateSystem{U}`: The target Earth-centered coordinate system.
- `t0`: Optional time offset to add to the CORSIKA hit time. Defaults to `0.0u"s"`.

# Returns
- A `CorsikaEvent` object containing a `Particle` with the CORSIKA hit time added to `t0` and
  the calculated relativistic speed.
"""
function CorsikaEvent(
    row,
    rot::V,
    center,
    cs_corsika::CoordinateSystem{U},
    cs_earth::CoordinateSystem{U};
    t0=0.0u"s"
) where {U<:Real, V<:Rotation}
    # Precompute the coordinate system transform (ideally called once per shower,
    # but the check cs_corsika==cs_earth short-circuits when they match)
    dir_rot, coord_offset = precompute_cs_transform(cs_corsika, cs_earth)
    return CorsikaEvent(row, rot, center, cs_earth, dir_rot, coord_offset; t0=t0)
end

"""
    CorsikaEvent(
        row, rot, center, cs_earth, dir_rot, coord_offset; t0=0.0u"s"
    )

Fast inner constructor that uses precomputed coordinate transform matrices.
Call `precompute_cs_transform` once per shower and pass the results here for
each particle row to avoid repeated matrix construction.
"""
function CorsikaEvent(
    row,
    rot::V,
    center,
    cs_earth::CoordinateSystem{U},
    dir_rot::SMatrix{3,3,Float64,9},
    coord_offset;
    t0=0.0u"s"
) where {U<:Real, V<:Rotation}
    # Direction: apply shower rotation, then precomputed CS transform
    raw_dir = rot * SVector(row.nx, row.ny, row.nz)
    earth_dir = dir_rot * raw_dir

    # Position: apply shower rotation + offset, then precomputed CS transform
    raw_pos = rot * SVector(row.x, row.y, row.z) .* u"m" .+ center .- SVector(0.0u"km", 0.0u"km", EARTH_RADIUS)
    earth_pos = dir_rot * (raw_pos .+ coord_offset)

    e = U(row.kinetic_energy * u"GeV")
    pdg = ParticleType(Int64(row.pdg))

    # Calculate particle speed — use haskey instead of try/catch
    speed = haskey(particle_masses, pdg) ? particle_speed(e, pdg) : speedoflight

    d = Direction(earth_dir, cs_earth)
    p = Coordinate(earth_pos, cs_earth)
    particle = Particle(pdg, e, p, d, U(t0 + row.time*u"s"), U(speed))
    return CorsikaEvent(particle, Float64(row.weight))
end

"""
    CorsikaEvent(
        row,
        cs_earth::CoordinateSystem{U},
        dir_rot::SMatrix{3,3,Float64,9},
        coord_offset;
        t0=0.0u"s"
    ) where {U<:Real}

Construct a `CorsikaEvent` from a CORSIKA 8 mesh-output parquet row.

Positions `(row.x, row.y, row.z)` are absolute ECEF metres (no shower-plane
rotation or Earth-radius offset). Directions `(row.nx, row.ny, row.nz)` are
unit vectors in the ECEF frame.  Use `precompute_cs_transform(ecefcoordinates,
cs_earth)` once per run to obtain `dir_rot` and `coord_offset`.
"""
function CorsikaEvent(
    row,
    cs_earth::CoordinateSystem{U},
    dir_rot::SMatrix{3,3,Float64,9},
    coord_offset;
    t0=0.0u"s"
) where {U<:Real}
    earth_dir = dir_rot * SVector(row.nx, row.ny, row.nz)

    # CORSIKA 8 ObservationMesh writes positions as displacement from the mesh
    # bounding-box centre (not absolute ECEF).  coord_offset already includes
    # the mesh centre shift: coord_offset = mesh_center_ecef - cs_earth.origin
    raw_pos   = SVector(row.x, row.y, row.z) .* u"m"
    earth_pos = dir_rot * (raw_pos .+ coord_offset)

    e   = U(row.kinetic_energy * u"GeV")
    pdg = ParticleType(Int64(row.pdg))
    speed = haskey(particle_masses, pdg) ? particle_speed(e, pdg) : speedoflight

    d = Direction(earth_dir, cs_earth)
    p = Coordinate(earth_pos, cs_earth)
    particle = Particle(pdg, e, p, d, U(t0 + row.time * u"s"), U(speed))
    return CorsikaEvent(particle, Float64(row.weight))
end

"""
    read_corsika_mesh(
        outdir::String,
        cs_earth::CoordinateSystem{T};
        t0=0.0u"s",
        filter_fxn::Function=x->true
    ) where {T<:Real}

Read particles from a `tambo_shower` (CORSIKA 8 mesh) output directory.

The directory must contain `particles/particles.parquet` and
`particles/config.yaml`.  CORSIKA 8's `ObservationMesh` writer stores particle
positions as displacements from the mesh bounding-box centre (in ECEF metres),
so this function reads the centre from `config.yaml` and folds it into the
coordinate transform.

# Arguments
- `outdir::String`: Top-level output directory passed to `tambo_shower` with `-f`.
- `cs_earth::CoordinateSystem{T}`: Target coordinate system for the returned particles.
- `t0`: Optional time offset added to CORSIKA hit times. Defaults to `0.0u"s"`.
- `filter_fxn::Function`: Optional per-event filter; unused by the iterator itself.

# Returns
- A `MultiParquetIterator` that yields `CorsikaEvent` objects.
"""
function read_corsika_mesh(
    outdir::String,
    cs_earth::CoordinateSystem{T};
    t0=0.0u"s",
    filter_fxn::Function=x->true
) where {T<:Real}
    pfile   = joinpath(outdir, "particles", "particles.parquet")
    cfgfile = joinpath(outdir, "particles", "config.yaml")
    isfile(pfile)   || throw(ArgumentError("No particles.parquet found in $outdir/particles/"))
    isfile(cfgfile) || throw(ArgumentError("No config.yaml found in $outdir/particles/"))

    # Read the mesh bounding-box centre (ECEF metres) from config.yaml.
    # Particle (x,y,z) are displacements from this centre, not absolute ECEF.
    cfg  = open(cfgfile) do f; YAML.load(f); end
    bmin = Float64.(cfg["mesh"]["bounds"]["min"])
    bmax = Float64.(cfg["mesh"]["bounds"]["max"])
    mesh_center = SVector{3,Float64}((bmin .+ bmax) ./ 2) .* u"m"

    dir_rot, coord_offset = precompute_cs_transform(ecefcoordinates, cs_earth)
    # Fold the mesh centre into the offset so the CorsikaEvent constructor
    # can simply do:  earth_pos = dir_rot * (raw_pos + coord_offset_with_center)
    coord_offset_with_center = coord_offset .+ mesh_center

    trans(row) = CorsikaEvent(row, cs_earth, dir_rot, coord_offset_with_center; t0=t0)
    return MultiParquetIterator([pfile], trans; T=CorsikaEvent)
end
