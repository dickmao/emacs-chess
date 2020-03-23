git clean -dfx
aclocal
autoconf
automake --add-missing
./configure --prefix=/home/dick/.local
make
cask install
