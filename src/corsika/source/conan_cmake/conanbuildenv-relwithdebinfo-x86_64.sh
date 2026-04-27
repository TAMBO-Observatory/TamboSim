script_folder="/n/home09/tkrishnan/corsika/conan_cmake"
echo "echo Restoring environment" > "$script_folder/deactivate_conanbuildenv-relwithdebinfo-x86_64.sh"
for v in CONAN_BISON_ROOT BISON_PKGDATADIR PATH LD_LIBRARY_PATH DYLD_LIBRARY_PATH M4
do
    is_defined="true"
    value=$(printenv $v) || is_defined="" || true
    if [ -n "$value" ] || [ -n "$is_defined" ]
    then
        echo export "$v='$value'" >> "$script_folder/deactivate_conanbuildenv-relwithdebinfo-x86_64.sh"
    else
        echo unset $v >> "$script_folder/deactivate_conanbuildenv-relwithdebinfo-x86_64.sh"
    fi
done


export CONAN_BISON_ROOT="/n/home09/tkrishnan/.conan2/p/b/bison69a19f915f2cd/p"
export BISON_PKGDATADIR="/n/home09/tkrishnan/.conan2/p/b/bison69a19f915f2cd/p/res/bison"
export PATH="/n/home09/tkrishnan/.conan2/p/b/bison69a19f915f2cd/p/bin:/n/home09/tkrishnan/.conan2/p/m43fe61932e2887/p/bin:$PATH"
export LD_LIBRARY_PATH="/n/home09/tkrishnan/.conan2/p/b/bison69a19f915f2cd/p/lib:/n/home09/tkrishnan/.conan2/p/b/readl62f9b1b1e9381/p/lib:$LD_LIBRARY_PATH"
export DYLD_LIBRARY_PATH="/n/home09/tkrishnan/.conan2/p/b/bison69a19f915f2cd/p/lib:/n/home09/tkrishnan/.conan2/p/b/readl62f9b1b1e9381/p/lib:$DYLD_LIBRARY_PATH"
export M4="/n/home09/tkrishnan/.conan2/p/m43fe61932e2887/p/bin/m4"