script_folder="/n/home09/tkrishnan/corsika/conan_cmake"
echo "echo Restoring environment" > "$script_folder/deactivate_conanrunenv-relwithdebinfo-x86_64.sh"
for v in OPENSSL_MODULES
do
    is_defined="true"
    value=$(printenv $v) || is_defined="" || true
    if [ -n "$value" ] || [ -n "$is_defined" ]
    then
        echo export "$v='$value'" >> "$script_folder/deactivate_conanrunenv-relwithdebinfo-x86_64.sh"
    else
        echo unset $v >> "$script_folder/deactivate_conanrunenv-relwithdebinfo-x86_64.sh"
    fi
done


export OPENSSL_MODULES="/n/home09/tkrishnan/.conan2/p/b/opensc20ff3cad4ee2/p/lib/ossl-modules"