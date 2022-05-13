#!/bin/bash

set -e

TAG=$(echo "${TAG}")
PAT=$(echo "${PAT}")
source_dir="${1:-$(pwd)}"
output_dir="${2:-$(pwd)}"
repository="${3:-thsfs/nano-node}"
workspace=$(pwd)

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

echo "Checking out the specified tag"
pushd "$source_dir"
if [[ ! -z $(ls -A "$source_dir" ) ]]; then
    echo "The source directory: ${source_dir} is not empty"
    exit 1
fi

git clone --branch "${TAG}" "https://github.com/${repository}" "nano-${TAG}"
pushd "nano-${TAG}"
git fetch --tags

read -r version_major version_minor version_revision <<< $( echo "${TAG}" | awk -F 'V' {'print $2'} | awk -F \. {'print $1, $2, $3'} )
previous_version_major=$(( version_major - 1 ))

echo "Getting the tag of the most recent previous version"
version_tags=$(git tag | grep -E "^(V(${previous_version_major}).[0-9]+(.[0-9]+)?)$" | sort)
for tag in $version_tags; do
    newest_previous_version=$tag
done
if [[ -z "$newest_previous_version" ]]; then
    echo "Didn't find a tag for the previous version: V${previous_version_major}.0 or V${previous_version_major}.0.0"
    exit 1
fi

develop_head=$(git show-ref -s origin/develop)
common_ancestor=$(git merge-base --octopus "${develop_head}" "${newest_previous_version}")

echo "Setting the python environment and running the changelog.py script"
apt-get install -y python3.8 python3-pip virtualenv python3-venv
(
    set -e

    virtualenv "${workspace}/venv" --python=python3.8
    source "${workspace}/venv/bin/activate"
    python -m pip install PyGithub mdutils
    set +x
    python "${workspace}/util/changelog.py" -p "${PAT}" -s "${common_ancestor}" -e "${TAG}"
    set -x

    if [ ! -s CHANGELOG.md ]; then
        echo "CHANGELOG not generated"
        exit 1
    else
        mv -vn CHANGELOG.md -t "${output_dir}"
    fi
    exit 0
) || exit 1
