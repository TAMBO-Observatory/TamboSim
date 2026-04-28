"""
    get_tambosim_path() -> String

Returns the TAMBO-MC repository root path. Uses the `TAMBOSIM_PATH` environment variable
if set, otherwise infers the path from the location of this source file.
"""
function get_tambosim_path()
    return get(ENV, "TAMBOSIM_PATH", dirname(@__DIR__))
end

"""
    get_git_commit_hash() -> Union{String, Nothing}

Retrieves the Git commit hash of the Tambo repository.
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
    get_version_string() -> String

Returns the Tambo package version string as recorded in its `Project.toml`.
"""
function get_version_string()
    string(pkgversion(Tambo))
end

"""
    relativize!(d::Dict)

Recursively resolves relative path strings in a dictionary against the package root directory.
Strings containing `/` but not starting with `/` are treated as relative paths.
Also handles the legacy `_TAMBOSIM_PATH_` placeholder for backward compatibility.

This function modifies the dictionary in-place.
"""
function relativize!(d::Dict)
    pkg_root = dirname(@__DIR__)
    tambo_data_path = get(ENV, "TAMBO_DATA_PATH", "")
    tambo_corsika_path = get(ENV, "TAMBO_CORSIKA_PATH", "")
    tambo_flupro_path = get(ENV, "TAMBO_FLUPRO_PATH", "")
    for (k, v) in pairs(d)
        if isa(v, String)
            v_new = replace(v, "_TAMBOSIM_PATH_" => pkg_root)
            v_new = replace(v_new, "_TAMBO_DATA_PATH_" => tambo_data_path)
            v_new = replace(v_new, "_TAMBO_CORSIKA_PATH_" => tambo_corsika_path)
            v_new = replace(v_new, "_TAMBO_FLUPRO_PATH_" => tambo_flupro_path)
            if v_new == v && contains(v, '/') && !startswith(v, '/')
                v_new = joinpath(pkg_root, v)
            end
            d[k] = v_new
        elseif isa(v, Dict)
            relativize!(v)
        end
    end
end
