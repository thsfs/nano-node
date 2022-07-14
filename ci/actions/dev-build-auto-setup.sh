#!/bin/bash

# This script checkes whether the develop branch contains new commits since the last develop build.
# If so, it pushes a tag for the next DB build and exports the $build_tag variable.
# Error exit codes: 1: invalid usage of the script. 2: no new change found since the last build.

source_dir="$(pwd)"
git_upstream="origin"

print_usage() {
    echo "$(basename ${0}) [OPTIONS]"
    echo "OPTIONS:"
    echo "  [-h]                 Print this help info."
    echo "  [-s <source_dir>]    Directory that contains the source-code. Default is \$PWD."
    echo "  [-u <git_upstream>]  Name of the git repository upstream. Default is \"${git_upstream}\"."
}

while getopts 'hs:u:' OPT; do
    case "${OPT}" in
    h)
        print_usage
        exit 0
        ;;
    s)
        source_dir="${OPTARG}"
        if [[ ! -d "$source_dir" ]]; then
            echo "Invalid source directory"
            exit 1
        fi
        ;;
    u)
        git_upstream="${OPTARG}"
        if [[ -z "$git_upstream" ]]; then
            echo "Invalid git upstream"
            exit 1
        fi
        ;;
    *)
        print_usage >&2
        exit 1
        ;;
    esac
done

set -o errexit
set -o nounset
set -o xtrace

current_version_major=$(grep -P "(set)(.)*(CPACK_PACKAGE_VERSION_MAJOR)" "${source_dir}/CMakeLists.txt" | grep -oP "([0-9]+)")
current_version_minor=$(grep -P "(set)(.)*(CPACK_PACKAGE_VERSION_MINOR)" "${source_dir}/CMakeLists.txt" | grep -oP "([0-9]+)")
current_version_pre_release=$(grep -P "(set)(.)*(CPACK_PACKAGE_VERSION_PRE_RELEASE)" "${source_dir}/CMakeLists.txt" | grep -oP "([0-9]+)")

if [[ ${current_version_pre_release} != "99" ]]; then
    echo "This is not the develop branch or the pre-release version is not properly set."
    exit 1
fi

pushd "$source_dir"
last_tag=""
version_tags=$(git tag | sort -r | grep -E "^(V(${current_version_major}).(${current_version_minor})(DB[0-9]+))$")
for tag in $version_tags; do
    if [[ -n "$tag" ]]; then
        last_tag=$tag
        echo "Found tag: $tag"
        break
    fi
done
popd

if [[ -z "$last_tag" ]]; then
    echo "No tag found"
    exit 1
fi

develop_head=$(cat "${source_dir}/.git/refs/heads/develop")
tag_head=$(cat "${source_dir}/.git/refs/tags/${last_tag}")

if [[ "$develop_head" == "$tag_head" ]]; then
    echo "No new commits for the develop build, the develop branch head matches the latest DB tag head!"
    exit 2
fi

latest_build_number=$(echo "$last_tag" | grep -oP "(DB[0-9]+)" | grep -oP "[0-9]+")
export build_number=$(( latest_build_number + 1 ))
export build_tag="V${current_version_major}.${current_version_minor}DB${build_number}"

#git tag "$build_tag"
#git push "$git_upstream" --tag "$build_tag"
