#!/bin/bash

set -eo pipefail

VERSION="0.1.0"
if [[ -z "${DOCTAVE_HOST}" ]]; then
    _DOCTAVE_HOST="$DOCTAVE_HOST"
else
    _DOCTAVE_HOST="https://docs.doctave.com"
fi

HELP_TEXT="Doctave Push $VERSION

Upload your documentation to Doctave.com. Add this script to your CI to have
always up-to-date docs. This tool can be configured via environment variables,
or via command line flags.

USAGE:
    doctave-push [OPTIONS] PATH

ARGS:
    <PATH>:
            The directory containing the doctave.yaml file.

OPTIONS:
    -t --upload-token:
            Upload token linked to the Doctave project. Find yours by going to
            doctave.com/settings/<team>/<project>.

            Not required if DOCTAVE_UPLOAD_TOKEN environment variable is set"

ZIPPED="/tmp/doctave-push-$RANDOM.zip"
POSITIONAL=()
while [[ $# -gt 0 ]]
do
key="$1"

case $key in
    -t|--upload-token)
    UPLOAD_TOKEN="$2"
    shift # past argument
    shift # past value
    ;;
    -h|--help)
    HELP="Y"
    shift # past argument
    ;;
    *)    # unknown option
    DOCS_PATH+=("$1") # save it in an array for later
    shift # past argument
    ;;
esac
done
set -- "${POSITIONAL[@]}" # restore positional parameters

if [ "$HELP" == "Y" ]; then
    echo "$HELP_TEXT"
    exit 0
fi

UPLOAD_TOKEN="${UPLOAD_TOKEN:-$DOCTAVE_UPLOAD_TOKEN}"

input_error() {
    echo "Error: $1."
    echo "Run \`doctave-push --help\` for usage instructions"
    exit 1
}

dependency_error() {
    echo "Could not find runtime dependency: $1"
    exit 1
}

detect_dependencies() {
    if ! command -v git &> /dev/null; then
        dependency_error "git"
    fi

    if ! command -v python &> /dev/null; then
        dependency_error "python"
    fi

    if ! command -v zip &> /dev/null; then
        dependency_error "zip"
    fi

    if [[ "$(python -V)" == "Python 2"* ]]; then
        PYTHON_VERSION=2
    else
        PYTHON_VERSION=3
    fi
}

validate_dir() {
    if [[ ${#DOCS_PATH[@]} == 0 ]]; then
        input_error "Missing path to docs directory"
    fi
    if [[ ${#DOCS_PATH[@]} != 1 ]]; then
        input_error "More than one docs directory path passed"
    fi

    DOCS_PATH="${DOCS_PATH[0]}"

    if ! [ -f "$DOCS_PATH/doctave.yaml" ]; then
        input_error "Could not find doctave.yaml in the provided path"
    fi

    if ! [ -d "$DOCS_PATH/docs" ]; then
        input_error "Could not find docs directory in the provided path"
    fi
}

print_upload_error() {
    local json
    json="$1"

    if ! $(echo $json | python -c 'import json,sys;obj=json.load(sys.stdin);' &> /dev/null); then
        echo "Push failed: Unexpected response from server."
        echo "$json"
        exit 1
    fi

    echo "Error pushing docs to Doctave:"
    if [[ $PYTHON_VERSION == 2 ]]; then
        echo "$(echo $json | python -c 'import json,sys;obj=json.load(sys.stdin);print obj["errors"][0]["detail"]')"
    else
        echo "$(echo $json | python -c 'import json,sys; print(json.load(sys.stdin)["errors"][0]["detail"])')"
    fi
}

detect_git_info() {
    GIT_SHA="$(git rev-parse HEAD)"
    GIT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
    GIT_AUTHOR="$(git show -s --format='%ae' HEAD)"
}

validate_dir
detect_dependencies
detect_git_info

zip -r $ZIPPED "$DOCS_PATH/doctave.yaml" "$DOCS_PATH/docs"

resp="$(curl -w "|%{http_code}" -H "Authorization: Bearer $UPLOAD_TOKEN" -F "git_sha=$GIT_SHA" -F "git_branch=$GIT_BRANCH" -F "git_author=$GIT_AUTHOR" -F docs="@$ZIPPED" "$_DOCTAVE_HOST"/uploads)"

body="$( echo "$resp" | cut -d '|' -f 1 )"
http_code="$( echo "$resp" | cut -d '|' -f 2 )"

if [[ $http_code == "201" ]]; then
    echo "Done!"
    exit 0
else
    print_upload_error "$body"
    exit $exit_status
fi
