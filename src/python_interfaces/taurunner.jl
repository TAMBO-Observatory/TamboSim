using PyCall

const tr = PyNULL()
const earth = PyNULL()
const clp = PyNULL()
const xs = PyNULL()
const chord = PyNULL()

function tr_startup()

    copy!(tr, pyimport("taurunner"))
    x = tr.body.earth
    copy!(earth, x.construct_earth())
    copy!(xs, tr.cross_sections.CrossSections(tr.cross_sections.XSModel.CSMS))
    copy!(clp, tr.proposal_interface.ChargedLeptonPropagator(earth, xs))
    copy!(chord, tr.track.chord)

end

# function run_taurunner(p:: Particle, θ:: Float64, depth:: Float64)
function run_taurunner(p, θ:: Float64, depth:: Float64)

    tr_p = tr.particle.Particle(p.pdg_mc, p.energy*units.eV, 0.0, xs)
    # We need to round here otherwise it will take forever. Sorry
    track = chord(theta=p.direction.θ, depth=round(depth, digits=3))
    rounded_depth = round(depth,digits=3)

    #for some reason 0.001 stalls 
    #hopefully this doesn't change things 
    if rounded_depth == 0.001 
        rounded_depth = rounded_depth + 1e-10 
    end 

    track = chord(theta=p.direction.θ,depth=rounded_depth)
    # return tr_p, track, earth, clp
    tr_d = tr.Propagate(tr_p, track, earth, clp)
    return tr_d.energy * units.eV, track.x_to_X(earth, tr_d.decay_position)[1]
end

function tr_propagate(ps::Vector{Particle}, ztambo::Float64, seed::Int)
    # Check that TR variables have been initiailized
    if chord == PyNULL() 
        tr_startup()
        tr.Casino.np.random.seed(seed)
        tr.Casino.pp.RandomGenerator.get().set_seed(seed)
    end 
    
    return tr_propagate.(ps, ztambo, seed)
end

function tr_propagate(p::Particle, ztambo::Float64, seed::Int)
    # Check that TR variables have been initiailized

    if chord == PyNULL()
        tr_startup()
    end

    tr.Casino.pp.RandomGenerator.get().set_seed(seed)
    tr.Casino.np.random.seed(seed)
    xb′ = p.position + SVector{3}([0, 0, ztambo + units.earthradius])
    depth = (units.earthradius - norm(xb′)) / units.earthradius
    # The neutrino does not pass through the Earth
    if depth <= 0
        return p, 0.0
    end
    ψ = acos(xb′.z / norm(xb′))
    θ_tr = p.direction.θ + ψ
    eout, X = run_taurunner(p, θ_tr, depth)
    xb′ -= SVector{3}([0, 0, ztambo + units.earthradius])
    return Particle(p.pdg_mc, eout, xb′, p.direction), X
end
