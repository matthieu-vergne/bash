#! /bin/bash

# Script to retrieve the SDSS image for a given astrophotograph (e.g. FIT or PNG image).
# It uses Docker to retrieve an astrometry.net image and produce the WCS data of the image.
# The SDSS image is then retrieved from the DESI Legacy Imaging Surveys website (legacysurvey.org).

ASTRO_INDEX_DIR="${ASTRO_INDEX_DIR:-"${HOME}/astrometry_indexes"}"
function show_help() {
	echo "Usage: $0 <image_file>"
	echo "Options:"
	echo "  -h, --help      Show this help message and exit"
	echo ""
	echo "Astrometry indexes are retrieved from: $ASTRO_INDEX_DIR"
	echo "To change it, set the ASTRO_INDEX_DIR environment variable."
	echo "To know how to download the indexes, check astrometry.net"
}

if [[ "$#" -ne 1 ]]; then
	>&2 echo "Error: Invalid number of arguments"
	show_help
	exit 1
fi

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
	show_help
	exit 0
fi

SOURCE_PATH="$1"

SOURCE_FILE="$(basename "$SOURCE_PATH")"
SOURCE_DIR="$(dirname "$(readlink -f "$SOURCE_PATH")")"
echo "Source directory: ${SOURCE_DIR}"
echo "Source file: ${SOURCE_FILE}"

WORK_DIR=$(mktemp -d)
cd "${WORK_DIR}"
echo "Working directory: ${PWD}"

cp "${SOURCE_DIR}/${SOURCE_FILE}" "${WORK_DIR}/${SOURCE_FILE}"

echo "Astrometry indexes: ${ASTRO_INDEX_DIR}"

# Generate WCS file
docker run --rm --user $(id -u):$(id -g) --volume "${WORK_DIR}:${WORK_DIR}" --workdir "${WORK_DIR}" --volume "${ASTRO_INDEX_DIR}:/usr/local/data" astrometrynet/solver:latest solve-field "${SOURCE_FILE}"

# Extract relevant data from WCS file
FILE_NAME="${SOURCE_FILE%.*}"
function retrieve() {
	local KEY="$1"
	# WCS file is a FIT file, with a header of "key = value" entries of 80 characters long each
	# We retrieve the value (3rd term of the entry) of the provided key
	cat "${FILE_NAME}.wcs" | sed -e 's/.\{80\}/\0\n/g' | grep "${KEY}" | awk '{print $3}'
}
CRVAL1=$(retrieve CRVAL1)
CRVAL2=$(retrieve CRVAL2)
CRPIX1=$(retrieve CRPIX1)
CRPIX2=$(retrieve CRPIX2)
CD1_1=$(retrieve CD1_1)
CD1_2=$(retrieve CD1_2)
CD2_1=$(retrieve CD2_1)
CD2_2=$(retrieve CD2_2)
IMAGEW=$(retrieve IMAGEW)
IMAGEH=$(retrieve IMAGEH)

# Retrieve SDSS image
SDSS_FILE="${FILE_NAME}-sdss.jpeg"
wget -O "${SDSS_FILE}" "https://www.legacysurvey.org/viewer/cutout-wcs/?layer=sdss&crval1=${CRVAL1}&crval2=${CRVAL2}&crpix1=${CRPIX1}&crpix2=${CRPIX2}&cd11=${CD1_1}&cd12=${CD1_2}&cd21=${CD2_1}&cd22=${CD2_2}&imagew=${IMAGEW}&imageh=${IMAGEH}"

# Export SDSS image to source directory
cp "${SDSS_FILE}" "${SOURCE_DIR}/${SDSS_FILE}"
