#!/bin/bash
# Usage: grade dir_or_archive [output]

# Ensure realpath 
realpath . &>/dev/null
HAD_REALPATH=$(test "$?" -eq 127 && echo no || echo yes)
if [ "$HAD_REALPATH" = "no" ]; then
  cat > /tmp/realpath-grade.c <<EOF
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

int main(int argc, char** argv) {
  char* path = argv[1];
  char result[8192];
  memset(result, 0, 8192);

  if (argc == 1) {
      printf("Usage: %s path\n", argv[0]);
      return 2;
  }
  
  if (realpath(path, result)) {
    printf("%s\n", result);
    return 0;
  } else {
    printf("%s\n", argv[1]);
    return 1;
  }
}
EOF
  cc -o /tmp/realpath-grade /tmp/realpath-grade.c
  function realpath () {
    /tmp/realpath-grade $@
  }
fi

INFILE=$1
if [ -z "$INFILE" ]; then
  CWD_KBS=$(du -d 0 . | cut -f 1)
  if [ -n "$CWD_KBS" -a "$CWD_KBS" -gt 20000 ]; then
    echo "Chamado sem argumentos."\
         "Supus que \".\" deve ser avaliado, mas esse diretório é muito grande!"\
         "Se realmente deseja avaliar \".\", execute $0 ."
    exit 1
  fi
fi
test -z "$INFILE" && INFILE="."
INFILE=$(realpath "$INFILE")
# grades.csv is optional
OUTPUT=""
test -z "$2" || OUTPUT=$(realpath "$2")
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
# Absolute path to this script
THEPACK="${DIR}/$(basename "${BASH_SOURCE[0]}")"
STARTDIR=$(pwd)

# Split basename and extension
BASE=$(basename "$INFILE")
EXT=""
if [ ! -d "$INFILE" ]; then
  BASE=$(echo $(basename "$INFILE") | sed -E 's/^(.*)(\.(c|zip|(tar\.)?(gz|bz2|xz)))$/\1/g')
  EXT=$(echo  $(basename "$INFILE") | sed -E 's/^(.*)(\.(c|zip|(tar\.)?(gz|bz2|xz)))$/\2/g')
fi

# Setup working dir
rm -fr "/tmp/$BASE-test" || true
mkdir "/tmp/$BASE-test" || ( echo "Could not mkdir /tmp/$BASE-test"; exit 1 )
UNPACK_ROOT="/tmp/$BASE-test"
cd "$UNPACK_ROOT"

function cleanup () {
  test -n "$1" && echo "$1"
  cd "$STARTDIR"
  rm -fr "/tmp/$BASE-test"
  test "$HAD_REALPATH" = "yes" || rm /tmp/realpath-grade* &>/dev/null
  return 1 # helps with precedence
}

# Avoid messing up with the running user's home directory
# Not entirely safe, running as another user is recommended
export HOME=.

# Check if file is a tar archive
ISTAR=no
if [ ! -d "$INFILE" ]; then
  ISTAR=$( (tar tf "$INFILE" &> /dev/null && echo yes) || echo no )
fi

# Unpack the submission (or copy the dir)
if [ -d "$INFILE" ]; then
  cp -r "$INFILE" . || cleanup || exit 1 
elif [ "$EXT" = ".c" ]; then
  echo "Corrigindo um único arquivo .c. O recomendado é corrigir uma pasta ou  arquivo .tar.{gz,bz2,xz}, zip, como enviado ao moodle"
  mkdir c-files || cleanup || exit 1
  cp "$INFILE" c-files/ ||  cleanup || exit 1
elif [ "$EXT" = ".zip" ]; then
  unzip "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".tar.gz" ]; then
  tar zxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".tar.bz2" ]; then
  tar jxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".tar.xz" ]; then
  tar Jxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".gz" -a "$ISTAR" = "yes" ]; then
  tar zxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".gz" -a "$ISTAR" = "no" ]; then
  gzip -cdk "$INFILE" > "$BASE" || cleanup || exit 1
elif [ "$EXT" = ".bz2" -a "$ISTAR" = "yes"  ]; then
  tar jxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".bz2" -a "$ISTAR" = "no" ]; then
  bzip2 -cdk "$INFILE" > "$BASE" || cleanup || exit 1
elif [ "$EXT" = ".xz" -a "$ISTAR" = "yes"  ]; then
  tar Jxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".xz" -a "$ISTAR" = "no" ]; then
  xz -cdk "$INFILE" > "$BASE" || cleanup || exit 1
else
  echo "Unknown extension $EXT"; cleanup; exit 1
fi

# There must be exactly one top-level dir inside the submission
# As a fallback, if there is no directory, will work directly on 
# tmp/$BASE-test, but in this case there must be files! 
function get-legit-dirs  {
  find . -mindepth 1 -maxdepth 1 -type d | grep -vE '^\./__MACOS' | grep -vE '^\./\.'
}
NDIRS=$(get-legit-dirs | wc -l)
test "$NDIRS" -lt 2 || \
  cleanup "Malformed archive! Expected exactly one directory, found $NDIRS" || exit 1
test  "$NDIRS" -eq  1 -o  "$(find . -mindepth 1 -maxdepth 1 -type f | wc -l)" -gt 0  || \
  cleanup "Empty archive!" || exit 1
if [ "$NDIRS" -eq 1 ]; then #only cd if there is a dir
  cd "$(get-legit-dirs)"
fi

# Unpack the testbench
tail -n +$(($(grep -ahn  '^__TESTBENCH_MARKER__' "$THEPACK" | cut -f1 -d:) +1)) "$THEPACK" | tar zx
cd testbench || cleanup || exit 1

# Deploy additional binaries so that validate.sh can use them
test "$HAD_REALPATH" = "yes" || cp /tmp/realpath-grade "tools/realpath"
cc -std=c11 tools/wrap-function.c -o tools/wrap-function \
  || echo "Compilation of wrap-function.c failed. If you are on a Mac, brace for impact"
export PATH="$PATH:$(realpath "tools")"

# Run validate
(./validate.sh 2>&1 | tee validate.log) || cleanup || exit 1

# Write output file
if [ -n "$OUTPUT" ]; then
  #write grade
  echo "@@@###grade:" > result
  cat grade >> result || cleanup || exit 1
  #write feedback, falling back to validate.log
  echo "@@@###feedback:" >> result
  (test -f feedback && cat feedback >> result) || \
    (test -f validate.log && cat validate.log >> result) || \
    cleanup "No feedback file!" || exit 1
  #Copy result to output
  test ! -d "$OUTPUT" || cleanup "$OUTPUT is a directory!" || exit 1
  rm -f "$OUTPUT"
  cp result "$OUTPUT"
fi

if ( ! grep -E -- '-[0-9]+' grade &> /dev/null ); then
   echo -e "Grade for $BASE$EXT: $(cat grade)"
fi

cleanup || true

exit 0

__TESTBENCH_MARKER__
�      �<]w�F�y֯@5�d����v�Ƶ�ԭc��N�s-W�ő̆"U~�N��=���>���	�c��C��7Iw�jN�%� �(!�s��/>[kb[[]����jS��ۃ����ꓵ��R�A����\y �����EAh� L�]��t�Y��M[��?�<'�,V���_^]��������|s\Dn?�=�Mw��W��r����� ��f����s�?z�8��ƹ\�~>�z�wt�{���i�[�织G��Vi��0���g`y% { 'P� Pg�CN7 �`.��oB} e�j��/<О�,��0�"�z�Š�v-�0��q���#���7C�2����Zƴ���je����\�_�0�,D�,�Q�˿Za��ݺ���'���t������r~���Z���%�#��;���iZ�g\l��.�v��>˱ϳ}>�k�*�n�u��Ƹ�t��V�
��1��п0�*U6J�+3�-A]���p�l�}���j�
��m?bn()\�vȊ�Ȣ��p8�ȴ]��������x{9�^��6,ǝ���T8еׁ9d��U ��!&��V�N��8Z��0�]h����`�mh�~����}����W�*����}�/���N����bp��X)q��k�Gl�P���f��beU*��@���6��'X���[(g�PZ�n��#���6
����]�����e	
�x��|�s�J�t���jdzsu�P�g���i%Q딶�X����@���my4F��?~�'3�A�a�,038� ����oF~>����_�䧟�Njɼ'1�	KQ�Cv����x�J�򥔑
Gz� ^Ҋ�H��tC8��'f����7�����U�Y���Vŷ�J^�z������Z�v�������2M��0_N��[cDЅ�V��c�&�U*�z�}��n4.V7���P�B'��	�ǊD-Ժ�J�	�W�8�*J��'��l5P��Յ��w)*{p����Ⱦ���pv�N�b�6PxU��ikc
�s���S���vm�P�H�t�V���t)���b�Z�*������*�})�d����e���d�\���D�ڤ<kR�ܡI*�b7�3�Y�R�q��o�E"�S�=ɂ��X��G%��I=�gw4�o����|\���"%�4v6$2:G��kp�y���r����켧����{��4y���eb���|"X,���������GD	�A$[�tv��D������n�z�R��3f�]Q�D*U.͙;
9o:����sD[��b%���c��u:?�P��1�I1��axAB�8��Sq�:Ǚ�g1`~��D9�v%���dY�%�k�@�p"�,MU���"�d�4���/`�$�`|b����!�+M�%���i���V�m{�c��!�[��,����H)�&�GѠ|B��Qi���s���+�'
.��G��2}"�Xfhp��8t���Y���+>D����7��hp�P��Y�����̰A�&P��[s���oP�1����O���u�H5�B
\�#�#↾��*���4-�"����3�߆¼�>�󶤬D���vl�#��V�Yψy��p����1�t���G��&���.�_�z��5Ҭ	��Bsac.aw�-�tBh��?�1�򝁗%rÏ;8 �9���7��c�� P%��p��"��8oH�\!���
���i6�IY��O����UWՑ���
���Q�w�7��Q�=�M-+K|JĘ
M!���?f[��d���Z~m�s �(�hL����A6��S�)Ѱ�	|�$�z\տ�����j?K˟�}�b�+�?�3����&�WW[�����h��߫������o��K����������;��.���w:;�mm��.���|��V�{5x����.n�8��ca�bA����K���%����7�Ŷc��m�u�*��m���?q��F��nz�+�!����XKw{�fO0��Ǹ�aq���r� �Z8�n�<���!��I�(a��lqA�ߡ̕ߋcc(s��#q��h����Ȟ��㍸ ��7����
y����?/��=b< �`�|ӵ<�^	 �؋��a������ҋ��3�N$v'�c֏��/
���E�3����+?}�'��֑�	�!
�����L��a�x$Gy�{�^��և�{Z�7�4IA-6�J!��]xX�p�^�M�o6!(�%�?��إ�P���̠�oԊ�?Z~}��!�?�����Z>�?y�2���"M����[;����c^�#}�x^*�xM�8	���H�`��܎h�1ƽ����u��P�O'3`�:7�on��p�^���|�)���v(�'���	�1�jǞ�O�O���)�/8%�.��WJn��,��^3����!������a~0�]�;�gϞ=z���Z�p
Kp��L} -�[��x�L���V%I (���x�������ÇM�!�Ų�ǰ��J%d���_�O�� �HZ��k֠1%z���1?rK
�n��D_M��w�q������oQ)[�W��f�i�gZ�����/3�����@-MB-��g��s�o��~��-A1�z���U�8�u�*`ssb�\01ٱ��Hb�+
�!�\>~,f�B��).>�ʼ��B��8ۄ����4�j5�#�`��%���ť�L��PQ���E��t��	q]��Y�����Ya2g��' �
�X�A�k4���p���f�Q��y�li�?����5�c�1~3/�O6ƌ�����j~��dmy��D��h�{%#}��K�B��U��(���/��+t乁��p٠]�qz��C��-r�Ш��k��t�f:��.����� ^�����^�\��Qh;Ɩ�o�p3�1�n�s&���NA:8�q���#w���
_��7�����E�=�k��.��R7^�St�8�Ǟ2���c��Q�8C����0����}ϵ�`��z陔�k��;fTJ���AB�	T� ���{9� ;2Qao�u��&:�B�EWP{�5������<Cf�;ޕ�YS�|_й�1Ϫ����������)ݪ��0���o���1�9E��At>�C�eW�x�y�0��d���%�}�boT��d���o���v|AW�?�З�굻�n�O+t2,ߏ�!�R��Cף+xwS�-�s�<E��~�&����T��O\z��n�����1�׵��� /��"
-�2�a+U�P��V�*��df�1�u;8�c�{�.Q�7�uӒ������*S�=;����u��3���cy�>��c���M[1�8 ��K��&&@�l�lAǌ��9C��k#vN�Z�?x�����{P�Uv�i��Nl�{[Ǉۻ�9j7%E�E�y�8�E"��#!7����f'�M.�6�a��r��O[{�;�p�K>%�M�YQP�IХwޝ�Y%���f�&r�E���v0~��a|/��]��N��M�o��3���Mm�;�Q�m��(�r�X�z��^�{�{bu5(�?5���Ӭ�#P` �G�&�^�B��y�tr�OB�6��	�yv(��)�ҹuY-�`WVs�ώ'w��K����!��(�)Ų�(^�N�5n\��#��D��0�S�_D&I��p��GW���}�"dG�s�VL�ߣ�)ۼ~?����Aw�Ӄ��,G� ��߂]]�uh-��Wk��r񐜀��aZ�ήm%���8�馣6iF�jlI�S���8��x�v{ޠ6yt�˵�<}x|���E-�6f!v�3��+2�2�,$�1�g̔�p�0�[!�����M1
_��)�[Zn%v�|梓f?u���%Wl*�b��&1�b����gx�5��۟̿>�L.+�t���^.�����a�'m"�����ݽ�ݣ�����є���ifXe����ye��E�y��'�ą�Nͧ�SSZb��M�c��&�jy�����9ٹ�9�t �3Q��ͽ���z�� � ]��LR�D����c��$�-4`@��!�m��b#�6-��=�Ձ�i�,�p@Z"v���6
�w�6f�fh�~X���.q@m�E.�E�F�1m�DOam�yE�@a�����N�aΤ:�kƖ1?�W�7��ld���R�cL1������z@E3�dq��Ѧb�x�$�<�Ժ.O����`R��{�捓���Oѕ�L�q;�z2�-B���L�����m"��1�ZNH��r���$���L�Jw�4^Qn���`#/q�#fNϦ;1��z�`�UD����,f�^5�C��	j|^��ɑԔI�-&��H:���Ö;0>�$&'-�p'YtZ�0��8o�`�7/"���z�&�-�^�l��ĕ�n��6a��Ij�PK�"_{��,���D�˕"f-�cv�5���y��r[*��]]���.�ތIq`���ty;�$���P�"��&������̃b��.�M�������W_R��gk���m��4��O<ƌ�����������d~��%�Z�ӷ�0J�1�FQ�7���u6�q�7�֪��Z5�r���'
�&��gie:@��~��O��ѥ+K{�߯��|�w�x� ��/��CF�����{~�A	K�W'|�����y�I��,����q��mI�mhe|�,[ �TY<�MY��eiJ�y�0�<�mo�>�ä�����(ihbHI�KAċ��y�+�Ҷ�ϲ/"��=i�"W��?R��*F@{Q�����m��Ќ+-�&قG	fI�cz/	%H Fi%.���<u�%א��@T�6�%h�6�M�U-1��*�����Q{�uŗ�[�{G��n:�q�ի��N����k����"�l��}F��A����e3��#'���\��%�lTN��B(�%���+�m�(1�j&�(A߀�?�Lg�ɝ&fE���%f��!N]̙J����W��jTIhA[�O��oN+�Q-7����xAaRl������'�w�� ��3�;��5�'���cf݁_Y�H31��9�|5��	e9*�QH��Bji�몮s�GuN�.��1N�!���P��L-T�X
��>�*[L���*�T�(�Փ򽉅���
��h�Z��Z4���O:�������w�����[�Q9�1�ы�Lyg]����)��6{����5�W�D�k�8	�i�Ϡ��QR�ui��B�w+_K����Mk������F��3� D�0�0t%�:�)��� �RęA��r!Ď���Pk����)�9�Ϥ��$	��v���Y=I��ݔ��n���X8�o�� �����X����¨�����Y�� ��p��:q|]�	(F>�>�����♑y�p�3Ƴ�2�� ~�P:�<�������9� c����F�=��0��CC��c��D����+4��±lٮ%�=��0��� %���i��v0�|��k{D�ᇿm�[�� "��'�m��m��m��m��m��m��m��m��m��m��m��m��m��m��m�����(g� x  