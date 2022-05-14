#!/bin/bash

# This script is just a wrapper for the changelog.py script, it has the functionality of automatically discovering the
# last version based on the tags saved in the repository.
# TODO: move the implemented functionalities of this script into the principal one: 'changelog.py'

set -e

TAG=$(echo "${TAG}")
PAT=$(echo "${PAT}")

print_usage() {
    echo "$(basename ${0}) [OPTIONS]"
    echo "OPTIONS:"
    echo "  [-h]               Print this help info."
    echo "  [-p <pat>]         Personal Access Token. Necessary if the PAT variable is not set"
    echo "  [-t <version_tag>  Version tag. Necessary if the TAG variable is not set. Must not be used with -s or -e"
    echo "                     The -t requires the formats: V1.0 that can be appended by RC1 or DB1. It'll"
    echo "                     look for the last version before it on the tag list."
    echo "  [-b <revision_begin> -e <revision_end>]  Instead of -t it is possible to pass the begin/end revisions"
    echo "  [-s <source_dir>]  Directory where the source-code will be downloaded to. Default is \$PWD"
    echo "  [-o <output_dir>]  Directory where the changelog will be generated. Default is \$PWD"
    echo "  [-w <workspace>]   Directory where the changelog.py can be found. Default is \$PWD"
    echo "  [-r <repository>]  Repository name to be passed to changelog.py. Default is 'nanocurrency/nano-node'"
}

revision_begin=""
revision_end=""
source_dir="$(pwd)"
output_dir="$(pwd)"
workspace="$(pwd)"
repository="nanocurrency/nano-node"

while getopts 'ht:t:p:b:e:s:o:w:r:' OPT; do
    case "${OPT}" in
    h)
        print_usage
        exit 0
        ;;
    t)
        if [[ -n "$TAG" ]]; then
            echo "Ignoring the TAG environment variable"
        fi
        TAG="${OPTARG}"
        ;;
    p)
        if [[ -n "$PAT" ]]; then
            echo "Ignoring the PAT environment variable"
        fi
        PAT="${OPTARG}"
        ;;
    b)
        revision_begin="${OPTARG}"
        if [[ -z "$revision_begin" ]]; then
            echo "Invalid revision"
            exit 1
        fi
        ;;
    e)
        revision_end="${OPTARG}"
        if [[ -z "$revision_end" ]]; then
            echo "Invalid revision"
            exit 1
        fi
        ;;
    s)
        source_dir="${OPTARG}"
        if [[ ! -d "$source_dir" ]]; then
            echo "Invalid source directory"
            exit 1
        fi
        ;;
    o)
        output_dir="${OPTARG}"
        if [[ ! -d "$output_dir" ]]; then
            echo "Invalid output directory"
            exit 1
        fi
        ;;
    w)
        workspace="${OPTARG}"
        if [[ ! -d "$workspace" ]]; then
            echo "Invalid workspace directory"
            exit 1
        fi
        ;;
    r)
        repository="${OPTARG}"
        if [[ -z "$repository" ]]; then
            echo "Invalid repository"
            exit 1
        fi
        ;;
    *)
        print_usage >&2
        exit 1
        ;;
    esac
done

if [[ -n "${TAG}" && (-n "${revision_begin}" || -n "${revision_end}") ]]; then
    echo "It should be set either the TAG or the begin/end revisions"
    exit 1
fi

if [[ (-n "${revision_start}" && -z "${revision_end}") || (-z "${revision_start}" && -n "${revision_end}") ]]; then
    echo "The options -b and -e require each other"
    exit 1
fi

# matches V1.0.0 and V1.0 formats
version_re="^(V[0-9]+.[0-9]+(.[0-9]+)?)$"
# matches V1.0.0RC1, V1.0.0DB1, V1.0RC1, V1.0DB1 formats
rc_beta_re="^(V[0-9]+.[0-9]+(.[0-9]+)?((RC[0-9]+)|(DB[0-9]+))?)$"

echo "Validating the required input variables TAG and PAT"
(
    set +x
    if [[ -z "$TAG" || -z "$PAT" ]]; then
        echo "TAG and PAT environment variables must be set"
        exit 1
    fi
    set -x

    if [[ ${TAG} =~ $version_re ]]; then
        exit 0
    elif [[ ${TAG} =~ $rc_beta_re ]]; then
        echo "RC and DB tags are not supported"
        exit 1
    else
        echo "The tag must match the pattern V1.0 or V1.0.0"
        exit 1
    fi
) || exit 1

set -x

read -r version_major version_minor version_revision <<< $( echo "${TAG}" | awk -F 'V' {'print $2'} | awk -F \. {'print $1, $2, $3'} )
if [[ -n "${version_revision}" ]]; then
    echo "Version revision is currently not supported by this script"
    exit 1
fi

echo "Checking out the specified tag"
pushd "$source_dir"
if [[ ! -z $(ls -A "$source_dir" ) ]]; then
    popd
    echo "The source directory: ${source_dir} is not empty"
    exit 1
fi

git clone --branch "${TAG}" "https://github.com/${repository}" "nano-${TAG}"
pushd "nano-${TAG}"
git fetch --tags

echo "Getting the tag of the most recent previous version"
newest_previous_version=""
previous_version_major="$version_major"
previous_version_minor="$version_minor"
while [[ -z "$newest_previous_version" ]]; do
    if [[ $previous_version_minor == "0" ]]; then
        previous_version_major=$(( previous_version_major-1 ))
        previous_version_minor="[0-9]+"
    else
        previous_version_major=$version_major
        previous_version_minor=$(( previous_version_minor-1 ))
    fi
    version_tags=$(git tag | sort -r | grep -E "^(V($previous_version_major).($previous_version_minor)(.[0-9]+)?)$")
    for tag in $version_tags; do
        if [[ -n "$tag" ]]; then
            newest_previous_version=$tag
            echo "Found tag: $tag"
            break
        fi
    done
done

if [[ -z "$newest_previous_version" ]]; then
    echo "Didn't find a tag for the previous version"
    exit 1
fi

develop_head=$(git show-ref -s origin/develop)
common_ancestor=$(git merge-base --octopus "${develop_head}" "${newest_previous_version}")

echo "Setting the python environment and running the changelog.py script"
#apt-get install -y python3.8 python3-pip virtualenv python3-venv
(
    set -e

    virtualenv "${workspace}/venv" --python=python3.8
    source "${workspace}/venv/bin/activate"
    python -m pip install PyGithub mdutils
    set +x
    python "${workspace}/util/changelog.py" --pat "${PAT}" -s "${common_ancestor}" -e "${TAG}" -r "${repository}"
    set -x

    if [ ! -s CHANGELOG.md ]; then
        echo "CHANGELOG not generated"
        exit 1
    else
        mv -vn CHANGELOG.md -t "${output_dir}"
    fi
    exit 0
) || exit 1
