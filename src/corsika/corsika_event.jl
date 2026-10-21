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

# One detector hit, as stamped in `q["corsika_hits"]` by `read_corsika_hits!`.
const CorsikaHitRec = NamedTuple{(:particle, :module_index, :weight),
                                 Tuple{Particle{Float64}, Int, Float64}}

"""
    precompute_cs_transform(cs_from::CoordinateSystem, cs_to::CoordinateSystem)

Precomputes the composed rotation and translation for converting coordinates
from `cs_from` to `cs_to`. Returns `(dir_rot, coord_offset)` where:
- `dir_rot`: rotation matrix for directions (rotation-only, no translation);
  also reused as the rotation step of the coordinate transform
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
        basedir::String,
        cs_earth::CoordinateSystem{T};
        t0=0.0u"s",
    ) where {T<:Real}

Read particles from one or more `tambo_shower` (CORSIKA 8 mesh) output directories.

Scans `basedir` for `shower_*/particles/` subdirectories, reads `config.yaml` and
`particles.parquet` from each completed shower, and returns a `MultiParquetIterator`
over all of them.  CORSIKA 8's `ObservationMesh` writer stores particle positions as
displacements from the mesh bounding-box centre (in ECEF metres), so the centre is
read from each shower's `config.yaml` and folded into that shower's coordinate transform.

A shower is considered incomplete and skipped (with a warning) if `summary.yaml` is
absent from its shower directory.

# Arguments
- `basedir::String`: Top-level output directory passed to `tambo_shower` with `-f`.
- `cs_earth::CoordinateSystem{T}`: Target coordinate system for the returned particles.
- `t0`: Optional time offset added to CORSIKA hit times. Defaults to `0.0u"s"`.

# Returns
- A `MultiParquetIterator` that yields `CorsikaEvent` objects.
"""
function read_corsika_mesh(
    basedir::String,
    cs_earth::CoordinateSystem{T};
    t0=0.0u"s",
) where {T<:Real}
    showers = _corsika_showers(basedir, cs_earth; t0)
    isempty(showers) && throw(ArgumentError("No completed showers found in $basedir"))
    return MultiParquetIterator([s.file for s in showers],
                                Function[s.transform for s in showers]; T=CorsikaEvent)
end

# The completed showers under `basedir`, as `(shower_dir, file, transform)`:
# the `shower_N` dir, its `particles.parquet`, and the row -> `CorsikaEvent`
# transform for it. Incomplete showers are skipped with a warning. Shared by
# `read_corsika_mesh` and de-thinning, which reads one shower at a time.
function _corsika_showers(basedir, cs_earth; t0=0.0u"s")
    dir_rot, coord_offset = precompute_cs_transform(ecefcoordinates, cs_earth)
    showers = NamedTuple{(:shower_dir, :file, :transform), Tuple{String,String,Function}}[]

    for pdir in glob("shower_*/particles/", basedir)
        if !isfile(joinpath(dirname(pdir), "summary.yaml"))
            @warn "$(dirname(pdir)) did not finish running."
            continue
        end

        pfile   = joinpath(pdir, "particles.parquet")
        cfgfile = joinpath(pdir, "config.yaml")
        if !isfile(pfile) || !isfile(cfgfile)
            @warn "Missing particles.parquet or config.yaml in $pdir, skipping."
            continue
        end

        # Read the mesh bounding-box centre (ECEF metres) from config.yaml.
        # Particle (x,y,z) are displacements from this centre, not absolute ECEF.
        cfg = open(cfgfile) do f; YAML.load(f); end
        bmin = Float64.(cfg["mesh"]["bounds"]["min"])
        bmax = Float64.(cfg["mesh"]["bounds"]["max"])
        mesh_center = SVector{3,Float64}((bmin .+ bmax) ./ 2) .* u"m"

        # Fold the mesh centre into the offset so the CorsikaEvent constructor
        # can simply do:  earth_pos = dir_rot * (raw_pos + coord_offset_with_center)
        coord_offset_with_center = coord_offset .+ mesh_center

        trans(row) = CorsikaEvent(row, cs_earth, dir_rot, coord_offset_with_center; t0=t0)
        push!(showers, (shower_dir=dirname(dirname(pdir)), file=pfile, transform=trans))
    end
    return showers
end
