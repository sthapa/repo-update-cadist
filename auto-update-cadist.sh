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
if ! gpg_wrapper --import "$GPG_HOME/$OSG_SECURITY_PUBKEY"; then
    message "Error importing OSG Security public key"
    message "Download URL: $OSG_SECURITY_PUBKEY_URL"
    exit 1
fi

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

    ## Get the CA certs distribution tarball by downloading the source RPM of
    ## the appropriate package and extracting the tarball from it.
    DOWNLOADDIR=$TMPROOT/download-$SUFFIX
    mkdir -p "$DOWNLOADDIR"
    pushd "$DOWNLOADDIR" >/dev/null
    # yumdownloader prints errors to stdout and is quiet when everything is ok
    yumdownloader --disablerepo=\* --enablerepo="$RPMREPO-source" --source "$RPM" 1>&2
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

    # Only by parsing the tarball name can we find out the version of the CA certs
    # TARBALL should be like "osg-certificates-1.59NEW.tar.gz"
    if ! echo "$TARBALL" | grep -Eq "^osg-certificates-[[:digit:]]+\.[[:digit:]]+${SUFFIX}.tar.gz$"; then
        message "$TARBALL: bad tarball name"
        message "Extracted from $RPMFILE"
        exit 1
    fi
    v=${TARBALL%${SUFFIX}.tar.gz}     # chop off the end
    VERSION_CA=${v#osg-certificates-} # and the beginning
    # VERSION_CA should be like "1.59"

    ## Download the GPG signature of the tarball from SVN and verify
    ## the tarball we extracted
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

    ## Save the tarball and the sigfile
    CADIR="${TMPROOT}/cadist/${VERSION_CA}${SUFFIX}"
    CATARBALL="${CADIR}/$TARBALL"
    CASIGFILE="${CADIR}/$SIGFILE"

    mkdir -p "${CADIR}"
    mv -f "$TARBALL" "$CATARBALL"
    mv -f "$SIGFILE" "$CASIGFILE"

    # Clean up
    popd >/dev/null
    rm -rf "$DOWNLOADDIR"


    ## Download the "version" file from SVN - this has a name like
    ## ca-certs-version-1.59NEW and is a txt file with the md5sum of the
    ## tarball in it.
    VERSIONFILE_URL=${CADISTREPO}/${CADISTREPORELEASETYPE}/ca-certs-version-${VERSION_CA}${SUFFIX}
    VERSIONFILE=${TMPROOT}/cadist/ca-certs-version${FILEEXT}
    if ! svn export -q --force "$VERSIONFILE_URL" "$VERSIONFILE"; then
        message "$VERSIONFILE: unable to download"
        message "Upstream URL: $VERSIONFILE_URL"
        exit 1
    fi

    ## Check the md5sums
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
    # also get the cacerts_md5sum.txt file which has the md5sums of the
    # individual certs inside the tarball
    mv certificates/cacerts_md5sum.txt ${TMPROOT}/cadist/cacerts_md5sum${FILEEXT}.txt
    # clean up
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

    ## Log a new version
    if [[ ! -d ${CAINSTALL}/${VERSION_CA}${SUFFIX} ]]; then
        echo "$(date) downloaded new version ${VERSION_CA}${SUFFIX}" >>${LOGREDIRECTFILENAME}.stdout
    fi
done

chmod -R ug+rwX "${TMPROOT}/cadist/"
chmod -R o+rX "${TMPROOT}/cadist/"
chown ${USER}:goc "${TMPROOT}/cadist/"

# if $CAINSTALL is /usr/local/repo/cadist:
#  NEWDIR is /usr/local/repo/.cadist.new
#  OLDDIR is /usr/local/repo/.cadist.old
NEWDIR=$(dirname "$CAINSTALL")/.$(basename "$CAINSTALL").new
OLDDIR=$(dirname "$CAINSTALL")/.$(basename "$CAINSTALL").old
# Do the actual update. Minimize the actual time that $CAINSTALL spends being non-existant
mkdir -p "$INSTALLBASE"
(
    set -e # bail on first error
    if [[ -e $CAINSTALL ]]; then
        rm -rf "$NEWDIR"
        rm -rf "$OLDDIR"

        # -T: never treat destination as a directory, i.e. always bail if
        # destination present and nonempty
        mv -fT "$TMPROOT/cadist" "$NEWDIR"
        mv -fT "$CAINSTALL" "$OLDDIR"
        mv -fT "$NEWDIR" "$CAINSTALL"
        rm -rf "$OLDDIR" || :
    else
        mv -fT "$TMPROOT/cadist" "$CAINSTALL"
    fi
) || message "Unable to update!"
