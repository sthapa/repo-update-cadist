#!/bin/bash
## minimal script to update cadist on repo1,repo2,repo-itb

TMP=/tmp
DATE=`date -u +%F_%H.%M.%S`
GOC="/usr/local"
INSTALLBASE="${GOC}/repo"
CADISTREPO="https://vdt.cs.wisc.edu/svn/certs/trunk/cadist"
CADISTREPORELEASETYPE="release"

LOGREDIRECTFILENAME="/var/log/auto-update-log"


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
                echo "Bad thing, if this happens something is really wrong"
                ;;
        esac

        tmpdir=$(mktemp -d)
        pushd $tmpdir 1>/dev/null 2>>${LOGREDIRECTFILENAME}.stderr
        yumdownloader --source $RPM 1>/dev/null 2>>${LOGREDIRECTFILENAME}.stderr
        rpm2cpio *.src.rpm | cpio --quiet -id '*.tar.gz' 1>/dev/null 2>>${LOGREDIRECTFILENAME}.stderr
        tarball=$(echo *.tar.gz)
        echo "$tarball" | grep -q "osg-certificates-.*${SUFFIX}.tar.gz" || \
            echo "Bad tarball name"
        v=${tarball%${SUFFIX}.tar.gz}
        VERSION_CA=${v#osg-certificates-}

        CATARBALL="${TMP}/cadist/${VERSION_CA}${SUFFIX}/osg-certificates-${VERSION_CA}${SUFFIX}.tar.gz"
        CASIGFILE="${TMP}/cadist/${VERSION_CA}${SUFFIX}/osg-certificates-${VERSION_CA}${SUFFIX}.tar.gz.sig"

        mkdir -p ${TMP}/cadist/${VERSION_CA}${SUFFIX}
        mv -f "$tarball" "$CATARBALL" 1>/dev/null 2>>${LOGREDIRECTFILENAME}.stderr
        popd 1>/dev/null 2>>${LOGREDIRECTFILENAME}.stderr
        rm -rf $tmpdir

        svn export --force ${CADISTREPO}/${CADISTREPORELEASETYPE}/ca-certs-version-${VERSION_CA}${SUFFIX} ${TMP}/cadist/ca-certs-version${FILEEXT}  1>/dev/null 2>>${LOGREDIRECTFILENAME}.stderr
        #svn export --force ${CADISTREPO}/${CADISTREPORELEASETYPE}/cacerts_md5sum-${VERSION_CA}${SUFFIX}.txt ${TMP}/cadist/cacerts_md5sum${FILEEXT}.txt  1>/dev/null 2>>${LOGREDIRECTFILENAME}.stderr
        #svn export --force ${CADISTREPO}/${CADISTREPORELEASETYPE}/osg-certificates-${VERSION_CA}${SUFFIX}.tar.gz ${CATARBALL}  1>/dev/null 2>>${LOGREDIRECTFILENAME}.stderr
        svn export --force ${CADISTREPO}/${CADISTREPORELEASETYPE}/osg-certificates-${VERSION_CA}${SUFFIX}.tar.gz.sig ${CASIGFILE}  1>/dev/null 2>>${LOGREDIRECTFILENAME}.stderr
        EXTRACT_FILES="certificates/CHANGES certificates/INDEX.html certificates/INDEX.txt"
        cd ${TMP}/cadist/${VERSION_CA}${SUFFIX}

        ## Extract INDEX.txt and CHANGES file; move them appropriately
        tar --no-same-owner -zxf ${CATARBALL} -C ${TMP}/cadist/${VERSION_CA}${SUFFIX}  1>/dev/null 2>>${LOGREDIRECTFILENAME}.stderr
        mv ${EXTRACT_FILES} ${TMP}/cadist/${VERSION_CA}${SUFFIX} 2>>${LOGREDIRECTFILENAME}.stderr
        mv certificates/cacerts_md5sum.txt ${TMP}/cadist/cacerts_md5sum${FILEEXT}.txt  1>/dev/null 2>>${LOGREDIRECTFILENAME}.stderr
        rm -rf ${TMP}/cadist/${VERSION_CA}${SUFFIX}/certificates/

        ## Create relevant symlinks including current distro
        cd ${TMP}/cadist/
        ln -f -s ${VERSION_CA}${SUFFIX}/CHANGES ${TMP}/cadist/CHANGES 1>/dev/null 2>>${LOGREDIRECTFILENAME}.stderr
        ln -f -s ${VERSION_CA}${SUFFIX}/INDEX.txt ${TMP}/cadist/INDEX.txt 1>/dev/null 2>>${LOGREDIRECTFILENAME}.stderr
        ln -f -s ${VERSION_CA}${SUFFIX}/INDEX.html ${TMP}/cadist/index.html 1>/dev/null 2>>${LOGREDIRECTFILENAME}.stderr

###     the following will throw an error saying files are the same, this indicated this update has already been done. Detect this for later use
        ln -f -n -s ${VERSION_CA}${SUFFIX} ${TMP}/cadist/ 1>/dev/null 2>/dev/null
	CHANGE_STATUS=$?

        ln -f -s ${VERSION_CA}${SUFFIX}/CHANGES ${TMP}/cadist/CHANGES-${CURRDIR} 1>/dev/null 2>>${LOGREDIRECTFILENAME}.stderr
        ln -f -s ${VERSION_CA}${SUFFIX}/INDEX.txt ${TMP}/cadist/INDEX-${CURRDIR}.txt 1>/dev/null 2>>${LOGREDIRECTFILENAME}.stderr
        ln -f -s ${VERSION_CA}${SUFFIX}/INDEX.html ${TMP}/cadist/index-${CURRDIR}.html 1>/dev/null 2>>${LOGREDIRECTFILENAME}.stderr
        ln -f -n -s ${VERSION_CA}${SUFFIX} ${TMP}/cadist/${CURRDIR} 1>/dev/null 2>>${LOGREDIRECTFILENAME}.stderr
        chmod -R ug+rwX ${TMP}/cadist/
        chmod -R o+rX ${TMP}/cadist/
        chown ${USER}:goc ${TMP}/cadist/

###     log a change event
	if [ $CHANGE_STATUS ]; then
	    echo "no-op for version ${VERSION_CA}" 1>/dev/null 2>/dev/null 
        else
	    TIMESTAMP=`date`
	    echo "$TIMESTAMP updated to version ${VERSION_CA}" 1>>${LOGREDIRECTFILENAME}.stdout 2>>${LOGREDIRECTFILENAME}.stderr
	fi
done
CAINSTALL=${INSTALLBASE}
rm -rf ${CAINSTALL}/cadist
mv ${TMP}/cadist ${CAINSTALL}
