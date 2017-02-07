#!/bin/bash
## minimal script to update cadist on repo1,repo2,repo-itb

set -o nounset

TMP=/tmp
DATE=`date -u +%F_%H.%M.%S`
GOC="/usr/local"
INSTALLBASE="${GOC}/repo"
CADISTREPO="https://vdt.cs.wisc.edu/svn/certs/trunk/cadist"
CADISTREPORELEASETYPE="release"

OSG_SECURITY_PUBKEY_URL=https://twiki.opensciencegrid.org/twiki/pub/Security/SecurityTeamMembers/osg-security-pubkey.asc
OSG_SECURITY_PUBKEY=$(basename "$OSG_SECURITY_PUBKEY_URL")

LOGREDIRECTFILENAME="/var/log/auto-update-log"

# Redirect all stderr output to file
exec 2>>$LOGREDIRECTFILENAME.stderr


GPG_HOME=$(mktemp -d)
trap 'rm -rf "$GPG_HOME"' EXIT

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
    echo '***' "$@" >&2
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

        tmpdir=$(mktemp -d)
        pushd $tmpdir >/dev/null
        yumdownloader --source $RPM >/dev/null
        rpmfile=$(/bin/ls *.src.rpm)
        if [[ ! -f $rpmfile ]]; then
            message "$RPM: unable to download from repos"
            exit 1
        fi
        rpm2cpio $rpmfile | cpio --quiet -id '*.tar.gz'
        TARBALL=$(/bin/ls *.tar.gz)
        if [[ ! -f $TARBALL ]]; then
            message "$rpmfile: couldn't extract tarball"
            exit 1
        fi
        if ! echo "$TARBALL" | grep -Eq "osg-certificates-[[:digit:]]+\.[[:digit:]]+${SUFFIX}.tar.gz"; then
            message "$TARBALL: bad tarball name"
            message "Extracted from $rpmfile"
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
            message "$tarball: GPG verification failed"
            exit 1
        fi

        CADIR="${TMP}/cadist/${VERSION_CA}${SUFFIX}"
        CATARBALL="${CADIR}/$TARBALL"
        CASIGFILE="${CADIR}/$SIGFILE"

        mkdir -p "${CADIR}"
        mv -f "$TARBALL" "$CATARBALL"
        mv -f "$SIGFILE" "$CASIGFILE"
        popd >/dev/null
        rm -rf $tmpdir

        VERSIONFILE_URL=${CADISTREPO}/${CADISTREPORELEASETYPE}/ca-certs-version-${VERSION_CA}${SUFFIX}
        VERSIONFILE=${TMP}/cadist/ca-certs-version${FILEEXT}
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
        tar --no-same-owner -zxf ${CATARBALL} -C "$CADIR"
        mv ${EXTRACT_FILES} "$CADIR"
        mv certificates/cacerts_md5sum.txt ${TMP}/cadist/cacerts_md5sum${FILEEXT}.txt
        rm -rf "${CADIR}/certificates/"

        ## Create relevant symlinks including current distro
        cd ${TMP}/cadist/
        ln -f -s ${VERSION_CA}${SUFFIX}/CHANGES ${TMP}/cadist/CHANGES
        ln -f -s ${VERSION_CA}${SUFFIX}/INDEX.txt ${TMP}/cadist/INDEX.txt
        ln -f -s ${VERSION_CA}${SUFFIX}/INDEX.html ${TMP}/cadist/index.html

###     the following will throw an error saying files are the same, this indicated this update has already been done. Detect this for later use
        ln -f -n -s ${VERSION_CA}${SUFFIX} ${TMP}/cadist/ 2>/dev/null
	CHANGE_STATUS=$?

        ln -f -s ${VERSION_CA}${SUFFIX}/CHANGES ${TMP}/cadist/CHANGES-${CURRDIR}
        ln -f -s ${VERSION_CA}${SUFFIX}/INDEX.txt ${TMP}/cadist/INDEX-${CURRDIR}.txt
        ln -f -s ${VERSION_CA}${SUFFIX}/INDEX.html ${TMP}/cadist/index-${CURRDIR}.html
        ln -f -n -s ${VERSION_CA}${SUFFIX} ${TMP}/cadist/${CURRDIR}
        chmod -R ug+rwX ${TMP}/cadist/
        chmod -R o+rX ${TMP}/cadist/
        chown ${USER}:goc ${TMP}/cadist/

###     log a change event
	if [ $CHANGE_STATUS ]; then
	    echo "no-op for version ${VERSION_CA}" 1>/dev/null 2>/dev/null
        else
	    TIMESTAMP=`date`
	    echo "$TIMESTAMP updated to version ${VERSION_CA}" 1>>${LOGREDIRECTFILENAME}.stdout
	fi
done
CAINSTALL=${INSTALLBASE}
rm -rf ${CAINSTALL}/cadist
mv ${TMP}/cadist ${CAINSTALL}
