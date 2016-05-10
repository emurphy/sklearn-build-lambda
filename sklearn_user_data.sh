#!/bin/bash
set -ex
set -o pipefail

yum update -y
yum install -y \
    atlas-devel \
    atlas-sse3-devel \
    blas-devel \
    gcc \
    gcc-c++ \
    lapack-devel \
    python27-devel

make_swap () {
    dd if=/dev/zero of=/swapfile bs=1024 count=1500000
    mkswap /swapfile
    chmod 0600 /swapfile
    swapon /swapfile
}

do_pip () {
    pip install --upgrade pip wheel
    IFS=' ' ; for pkg in numpy sklearn pandas xgboost numexpr; do
        pip install --use-wheel $pkg
    done
}

strip_virtualenv () {
    echo "venv original size $(du -sh $VIRTUAL_ENV | cut -f1)"
    find $VIRTUAL_ENV/lib64/python2.7/site-packages/ -name "*.so" -print |  xargs strip || true
    echo "venv stripped size $(du -sh $VIRTUAL_ENV | cut -f1)"
    # numpy, scipy, and sklearn have duplicate copies of a couple of shared libraries. make them share
    #NUMPY_LIBDIR=$VIRTUAL_ENV/lib64/python2.7/site-packages/numpy/.libs
    #SCIPY_LIBDIR=$VIRTUAL_ENV/lib64/python2.7/site-packages/scipy/.libs
    #SKLEARN_LIBDIR=$VIRTUAL_ENV/lib64/python2.7/site-packages/sklearn/.libs
    #rm -f $NUMPY_LIBDIR/lib*
    #(cd $NUMPY_LIBDIR; ln -s ../sklearn/.libs/lib* .)
    #rm -f $SCIPY_LIBDIR/lib*
    #(cd $SCIPY_LIBDIR; ln -s ../sklearn/.libs/lib* .)
    # save a little more space by removing source where we have a .pyc
    find $VIRTUAL_ENV  -name "*.pyc" -print |  sed s/.pyc$/.py/ | xargs rm -f
    echo "venv consolidated & source removed size $(du -sh $VIRTUAL_ENV | cut -f1)"

    pushd $VIRTUAL_ENV/lib64/python2.7/site-packages/ && zip --symlinks -r -9 -q ~/venv.zip * ; popd
    echo "site-packages compressed size $(du -sh ~/venv.zip | cut -f1)"

    pushd $VIRTUAL_ENV && zip --symlinks -r -q ~/full-venv.zip * ; popd
    echo "venv compressed size $(du -sh ~/full-venv.zip | cut -f1)"
}

upload () {
    inst_id=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
    aws s3 cp /root/venv.zip "s3://tmp.serverlesscode.com/sklearn/${inst_id}-site-pkgs.zip"
    aws s3 cp /root/full-venv.zip "s3://tmp.serverlesscode.com/sklearn/${inst_id}-full-venv.zip"
}

shared_libs () {
    libdir="$VIRTUAL_ENV/lib64/python2.7/site-packages/lib/"
    mkdir -p $VIRTUAL_ENV/lib64/python2.7/site-packages/lib || true
    cp /usr/lib64/atlas/* $libdir
    cp /usr/lib64/libquadmath.so.0 $libdir
    cp /usr/lib64/libgfortran.so.3 $libdir
}

main () {
    #make_swap

    /usr/bin/virtualenv \
        --python /usr/bin/python sklearn_build \
        --always-copy \
        --no-site-packages
    source sklearn_build/bin/activate

    do_pip

    shared_libs

    strip_virtualenv

    # done with the venv
    deactivate

    #upload
}
main
