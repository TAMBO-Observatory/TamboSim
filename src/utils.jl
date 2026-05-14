"""
    get_tambosim_path() -> String

Returns the TamboSim package root path. Uses the `TAMBOSIM_PATH` environment variable
if set, otherwise infers the path from the location of this source file.
"""
function get_tambosim_path()
    return get(ENV, "TAMBOSIM_PATH", dirname(@__DIR__))
end

"""
    get_git_commit_hash() -> Union{String, Nothing}

Retrieves the Git commit hash of the TamboSim repository.
"""
function get_git_commit_hash()::Union{String, Nothing}
    try
        repo = LibGit2.GitRepo(get_tambosim_path())
        return LibGit2.string(LibGit2.head_oid(repo))
    catch
        return nothing
    end
end

"""
    get_git_tag() -> Union{String, Nothing}

Returns the name of a Git tag pointing at the current HEAD commit of the
TamboSim repository, or `nothing` if no tag points at HEAD. Both lightweight
and annotated tags are considered; the first match is returned.
"""
function get_git_tag()::Union{String, Nothing}
    try
        repo = LibGit2.GitRepo(get_tambosim_path())
        head = LibGit2.head_oid(repo)
        for name in LibGit2.tag_list(repo)
            commit = LibGit2.peel(LibGit2.GitCommit, LibGit2.GitObject(repo, name))
            if LibGit2.GitHash(commit) == head
                return name
            end
        end
        return nothing
    catch
        return nothing
    end
end

"""
    is_git_dirty() -> Bool

Returns `true` if the TamboSim repository working tree has uncommitted changes,
`false` otherwise (including when the repository cannot be opened).
"""
function is_git_dirty()::Bool
    try
        return LibGit2.isdirty(LibGit2.GitRepo(get_tambosim_path()))
    catch
        return false
    end
end

"""
    get_version_string() -> String

Returns the TamboSim package version string as recorded in its `Project.toml`.
"""
function get_version_string()
    string(pkgversion(TamboSim))
end

"""
    relativize!(d::Dict)

Recursively resolve path-string entries in a parsed config dictionary
against the TamboSim package directory and well-known environment
variables.

For every string-valued entry (including nested dicts):

- `_TAMBOSIM_PATH_` is substituted with the TamboSim package root (see
  `get_tambosim_path`).
- `_TAMBO_DATA_PATH_`, `_TAMBO_CORSIKA_PATH_`, and `_TAMBO_FLUPRO_PATH_`
  are substituted with the values of the `TAMBO_DATA_PATH`,
  `TAMBO_CORSIKA_PATH`, and `TAMBO_FLUPRO_PATH` environment variables
  respectively (empty string if unset). These let pipeline configs
  point at host-mounted data volumes, container-baked CORSIKA/FLUKA
  installs, etc. without being edited per-deployment.
- A string with none of the above placeholders that contains `/` and
  does not start with `/` is treated as a package-relative path and
  joined to the package root.

Modifies `d` in place.
"""
function relativize!(d::Dict)
    pkg_root = get_tambosim_path()
    tambo_data_path    = get(ENV, "TAMBO_DATA_PATH",    "")
    tambo_corsika_path = get(ENV, "TAMBO_CORSIKA_PATH", "")
    tambo_flupro_path  = get(ENV, "TAMBO_FLUPRO_PATH",  "")
    for (k, v) in pairs(d)
        if isa(v, String)
            v_new = replace(v, "_TAMBOSIM_PATH_"      => pkg_root)
            v_new = replace(v_new, "_TAMBO_DATA_PATH_"    => tambo_data_path)
            v_new = replace(v_new, "_TAMBO_CORSIKA_PATH_" => tambo_corsika_path)
            v_new = replace(v_new, "_TAMBO_FLUPRO_PATH_"  => tambo_flupro_path)
            if v_new == v && contains(v, '/') && !startswith(v, '/')
                v_new = joinpath(pkg_root, v)
            end
            d[k] = v_new
        elseif isa(v, Dict)
            relativize!(v)
        end
    end
end
