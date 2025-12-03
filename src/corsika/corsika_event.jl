struct CorsikaEvent{T<:Real}
    particle::Particle{T}
    time::Quantity{T, tdim, typeof(u"s")}
    weight::T
end

function read_corsika(
    basedir::String,
    cs_corsika::CoordinateSystem{T},
    cs_earth::CoordinateSystem{T},
    filter_fxn::Function=x->true
) where {T<:Real}

    config = open("$(basedir)/particles/config.yaml") do file
        YAML.load(file)
    end

    rot = RotMatrix(SMatrix{3, 3, T, 9}([
        config["x-axis"]...;
        config["y-axis"]...;
        config["plane"]["normal"]
    ]))

    dset = Parquet2.Dataset("$(basedir)/particles/particles.parquet")
    rows = Tables.rows(dset)
    events = CorsikaEvent{T}[]
    for row in rows
        particle = Particle(row, rot, config["plane"]["center"], cs_corsika, cs_earth)
        if ~filter_fxn(particle)
            continue
        end
        event = CorsikaEvent(particle, T(row.time * u"s"), T(row.weight))
        push!(events, event)
    end
    return events
end

function Particle(
    row::T,
    rot::V,
    center,
    cs_corsika::CoordinateSystem{U},
    cs_earth::CoordinateSystem{U},
) where {T<:Tables.ColumnsRow, U<:Real, V<:Rotation}
    d = Direction(rot * [row.nx, row.ny, row.nz], cs_corsika)
    p = Coordinate((rot * [row.x, row.y, row.z] .+ center) .* u"m", cs_corsika)
    e = U(row.kinetic_energy * u"GeV")
    pdg = Int64(row.pdg)
    return Particle(pdg, e, convert(cs_earth, p), convert(cs_earth, d))
end
