#!/bin/sh -e

scriptpath=$(readlink -f "$0")
llgosrcdir=$(dirname "$scriptpath")
cd $llgosrcdir

gofrontendrepo=https://code.google.com/p/gofrontend
gofrontendrev=15a24202fa42

gccrepo=svn://gcc.gnu.org/svn/gcc/trunk
gccrev=219477

gotoolsrepo=https://go.googlesource.com/tools
gotoolsrev=d4e70101500b43ffe705d4c45e50dd4f1c8e3b2e

linerrepo=https://github.com/peterh/liner.git
linerrev=1bb0d1c1a25ed393d8feb09bab039b2b1b1fbced

tempdir=$(mktemp -d /tmp/update_third_party.XXXXXX)
gofrontenddir=$tempdir/gofrontend
gotoolsdir=$tempdir/go.tools
linerdir=third_party/liner

rm -rf third_party
mkdir -p third_party/gofrontend third_party/gotools

# --------------------- gofrontend ---------------------

hg clone -r $gofrontendrev $gofrontendrepo $gofrontenddir

cp -r $gofrontenddir/LICENSE $gofrontenddir/libgo third_party/gofrontend

# Apply a diff that eliminates use of the unnamed struct extension beyond what
# -fms-extensions supports.
(cd third_party/gofrontend && patch -p1) < libgo-noext.diff
# Apply a diff that disables testing of packages known to fail.
(cd third_party/gofrontend && patch -p1) < libgo-check-failures.diff
find third_party/gofrontend -name '*.orig' -exec rm \{\} \;

# Remove GPL licensed files.
rm \
  third_party/gofrontend/libgo/testsuite/libgo.testmain/testmain.exp \
  third_party/gofrontend/libgo/testsuite/lib/libgo.exp \
  third_party/gofrontend/libgo/testsuite/config/default.exp

# --------------------- gcc ---------------------

# Some dependencies are stored in the gcc repository.
# TODO(pcc): Ask iant about mirroring these dependencies into gofrontend.

for f in config-ml.in depcomp install-sh ltmain.sh missing ; do
  svn cat -r $gccrev $gccrepo/$f > third_party/gofrontend/$f
done

mkdir -p third_party/gofrontend/include third_party/gofrontend/libgcc

# Copy in our versions of GCC files.
cp include/dwarf2.h third_party/gofrontend/include/
cp include/filenames.h third_party/gofrontend/include/
cp include/unwind-pe.h third_party/gofrontend/libgcc/

# Note: this expects the llgo source tree to be located at llvm/tools/llgo.
cp ../../autoconf/config.guess third_party/gofrontend/
cp ../../autoconf/config.sub third_party/gofrontend/

for d in libbacktrace libffi ; do
  svn export -r $gccrev $gccrepo/$d third_party/gofrontend/$d
done

# Remove GPL licensed files, and files that confuse our license check.
rm \
  third_party/gofrontend/libffi/ChangeLog \
  third_party/gofrontend/libffi/doc/libffi.texi \
  third_party/gofrontend/libffi/msvcc.sh \
  third_party/gofrontend/libffi/testsuite/config/default.exp \
  third_party/gofrontend/libffi/testsuite/libffi.call/call.exp \
  third_party/gofrontend/libffi/testsuite/libffi.complex/complex.exp \
  third_party/gofrontend/libffi/testsuite/libffi.go/go.exp \
  third_party/gofrontend/libffi/testsuite/libffi.special/special.exp \
  third_party/gofrontend/libffi/testsuite/lib/libffi.exp \
  third_party/gofrontend/libffi/testsuite/lib/target-libpath.exp \
  third_party/gofrontend/libffi/testsuite/lib/wrapper.exp

# The build requires these files to exist.
touch \
  third_party/gofrontend/include/dwarf2.def \
  third_party/gofrontend/libffi/doc/libffi.texi

# --------------------- go.tools ---------------------

git clone $gotoolsrepo $gotoolsdir
(cd $gotoolsdir && git checkout $gotoolsrev)

cp -r $gotoolsdir/LICENSE $gotoolsdir/go third_party/gotools

# Vendor the go.tools repository.
find third_party/gotools -name '*.go' | xargs sed -i -e \
  's,"golang.org/x/tools/,"llvm.org/llgo/third_party/gotools/,g'

# --------------------- peterh/liner -----------------

git clone $linerrepo $linerdir
(cd $linerdir && git checkout $linerrev && rm -rf .git)

# --------------------- license check ---------------------

# We don't want any GPL licensed code without an autoconf/libtool
# exception, or any GPLv3 licensed code.

for i in `grep -lr 'General Public License' third_party` ; do
  if grep -q 'configuration script generated by Autoconf, you may include it under' $i || \
     grep -q 'is built using GNU Libtool, you may include this file under the' $i ; then
    :
  else
    echo "$i: license check failed"
    exit 1
  fi
done

if grep -qr GPLv3 third_party ; then
  echo "`grep -lr GPLv3 third_party`: license check failed"
  exit 1
fi

rm -rf $tempdir