#!/bin/bash
## minimal script to update cadist on repo1,repo2,repo-itb

set -o nounset

TMPROOT=$(mktemp -d)
trap 'rm -rf "$TMPROOT"' EXIT
GOC=/usr/local
INSTALLBASE=${GOC}/repo
CAINSTALL=${INSTALLBASE}/cadist
CADISTREPO="https://vdt.cs.wisc.edu/svn/certs/trunk/cadist"
CADISTREPORELEASETYPE="release"
RPMREPO=osg

OSG_SECURITY_PUBKEY_URL=https://twiki.opensciencegrid.org/twiki/pub/Security/SecurityTeamMembers/osg-security-pubkey.asc
OSG_SECURITY_PUBKEY=$(basename "$OSG_SECURITY_PUBKEY_URL")

LOGREDIRECTFILENAME="/var/log/auto-update-log"

# Redirect all stderr output to file
exec 2>>$LOGREDIRECTFILENAME.stderr


GPG_HOME=$TMPROOT/GPG_HOME
mkdir -p "$GPG_HOME"

# gpg is noisy and sends output to stderr even when things are going fine
# silence output unless there is an error
gpg_wrapper () {
    local outputfile ret
    outputfile=$(mktemp)
    gpg --homedir=$GPG_HOME "$@"  >$outputfile 2>&1
    ret=$?
    if [[ $ret != 0 ]]; then
        cat $outputfile 1>&2
    fi
    rm -f $outputfile
    return $ret
}

message () {
    echo "$(date)" "$@" >&2
}

wget -q "$OSG_SECURITY_PUBKEY_URL" -O "$GPG_HOME/$OSG_SECURITY_PUBKEY"
gpg_wrapper --import "$GPG_HOME/$OSG_SECURITY_PUBKEY"

for TYPES in NEW IGTFNEW; do
    SUFFIX=$TYPES
    case ${TYPES} in
        IGTFNEW)
            SYMEXT="igtf-new"
            FILEEXT="-igtf-new"
            CURRDIR="igtf-new"
            RPM="igtf-ca-certs"
            ;;
        NEW)
            SYMEXT="new"
            FILEEXT="-new"
            CURRDIR="new"
            RPM="osg-ca-certs"
            ;;
        *)
            message "Bad thing, if this happens something is really wrong"
            exit 1
            ;;
    esac

    DOWNLOADDIR=$TMPROOT/download-$SUFFIX
    mkdir -p "$DOWNLOADDIR"
    pushd "$DOWNLOADDIR" >/dev/null
    yumdownloader --disablerepo=\* --enablerepo="$RPMREPO-source" --source "$RPM" >/dev/null
    RPMFILE=$(/bin/ls *.src.rpm)
    if [[ ! -f $RPMFILE ]]; then
        message "$RPM: unable to download from repos"
        exit 1
    fi
    rpm2cpio "$RPMFILE" | cpio --quiet -id '*.tar.gz'
    TARBALL=$(/bin/ls *.tar.gz)
    if [[ ! -f $TARBALL ]]; then
        message "$RPMFILE: couldn't extract tarball"
        exit 1
    fi
    if ! echo "$TARBALL" | grep -Eq "^osg-certificates-[[:digit:]]+\.[[:digit:]]+${SUFFIX}.tar.gz$"; then
        message "$TARBALL: bad tarball name"
        message "Extracted from $RPMFILE"
        exit 1
    fi
    v=${TARBALL%${SUFFIX}.tar.gz}
    VERSION_CA=${v#osg-certificates-}
    SIGFILE=${TARBALL}.sig
    SIGFILE_URL=${CADISTREPO}/${CADISTREPORELEASETYPE}/${SIGFILE}
    if ! svn export -q --force "$SIGFILE_URL" "$SIGFILE"; then
        message "$SIGFILE: unable to download"
        message "Upstream URL: $SIGFILE_URL"
        exit 1
    fi
    if ! gpg_wrapper --verify "$SIGFILE"; then
        message "$TARBALL: GPG verification failed"
        exit 1
    fi

    CADIR="${TMPROOT}/cadist/${VERSION_CA}${SUFFIX}"
    CATARBALL="${CADIR}/$TARBALL"
    CASIGFILE="${CADIR}/$SIGFILE"

    mkdir -p "${CADIR}"
    mv -f "$TARBALL" "$CATARBALL"
    mv -f "$SIGFILE" "$CASIGFILE"
    popd >/dev/null
    rm -rf "$DOWNLOADDIR"

    VERSIONFILE_URL=${CADISTREPO}/${CADISTREPORELEASETYPE}/ca-certs-version-${VERSION_CA}${SUFFIX}
    VERSIONFILE=${TMPROOT}/cadist/ca-certs-version${FILEEXT}
    if ! svn export -q --force "$VERSIONFILE_URL" "$VERSIONFILE"; then
        message "$VERSIONFILE: unable to download"
        message "Upstream URL: $VERSIONFILE_URL"
        exit 1
    fi

    expected_md5sum=$(
        perl -lne '/^\s*tarball_md5sum\s*=\s*(\w+)/ and print "$1"' \
            "$VERSIONFILE")
    actual_md5sum=$(md5sum "$CATARBALL" | awk '{print $1}')

    if [[ $expected_md5sum != $actual_md5sum ]]; then
        message "$CATARBALL: md5sum mismatch"
        message "Expected: $expected_md5sum"
        message "Actual:   $actual_md5sum"
        exit 1
    fi

    EXTRACT_FILES="certificates/CHANGES certificates/INDEX.html certificates/INDEX.txt"
    cd "$CADIR"

    ## Extract INDEX.txt and CHANGES file; move them appropriately
    tar --no-same-owner -zxf "${CATARBALL}" -C "$CADIR"
    mv ${EXTRACT_FILES} "$CADIR"
    mv certificates/cacerts_md5sum.txt ${TMPROOT}/cadist/cacerts_md5sum${FILEEXT}.txt
    rm -rf "${CADIR}/certificates/"

    ## Create relevant symlinks including current distro
    cd ${TMPROOT}/cadist/
    ln -f -s ${VERSION_CA}${SUFFIX}/CHANGES ${TMPROOT}/cadist/CHANGES
    ln -f -s ${VERSION_CA}${SUFFIX}/INDEX.txt ${TMPROOT}/cadist/INDEX.txt
    ln -f -s ${VERSION_CA}${SUFFIX}/INDEX.html ${TMPROOT}/cadist/index.html

    ln -f -s ${VERSION_CA}${SUFFIX}/CHANGES ${TMPROOT}/cadist/CHANGES-${CURRDIR}
    ln -f -s ${VERSION_CA}${SUFFIX}/INDEX.txt ${TMPROOT}/cadist/INDEX-${CURRDIR}.txt
    ln -f -s ${VERSION_CA}${SUFFIX}/INDEX.html ${TMPROOT}/cadist/index-${CURRDIR}.html
    ln -f -n -s ${VERSION_CA}${SUFFIX} ${TMPROOT}/cadist/${CURRDIR}
    chmod -R ug+rwX ${TMPROOT}/cadist/
    chmod -R o+rX ${TMPROOT}/cadist/
    chown ${USER}:goc ${TMPROOT}/cadist/

    ## Log a new version
    if [[ ! -d ${CAINSTALL}/${VERSION_CA}${SUFFIX} ]]; then
        echo "$(date) updated to version ${VERSION_CA}${SUFFIX}" >>${LOGREDIRECTFILENAME}.stdout
    fi
done
mkdir -p "$INSTALLBASE"
rm -rf "$CAINSTALL"
mv "$TMPROOT/cadist" "$CAINSTALL"
