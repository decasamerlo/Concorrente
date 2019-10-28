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
�      �<�v�6����3jB��e5�8r�&J7���c�[�k����L(R��4I������)�b;�$HQ��:��]��D$8�f��!�s�.�>[kb{���o�Q�����^���nmu[[�ֽf��yԽ��GRڢ 4}�{�î�`1ܲ���-L�z�|+���;��Z�_���図�8rG���w��2�o}����뭭�=h���7��r���h��n��.J?��;:�x���[�/��{����al;l�O���J �N��A��~�&�mCx�\�&�n@}ek��.<�^�,��0�"���b�k;��⇨BCuͩ�L�!hDZERK-c�PN�jebNLdy.����4K|V���V��׿1��9h��^��[��n'�����z��v�vGNd1x���;%�˷�I��r��l��&욺J��=y��)��U���#�(!�.L��@��|d�5�%�� 33�@���s�`�YM@UA���-��%�+�Y�١!��1|�Դ]�L2J&ė�
����Na������
Ǻ�c`N�c�*���W�qD��3�-�0�]h���%1�|z��DT/�G�����^�(r��3$򕾈�O;����ؤG�J���_���<eӀ����34kؿ2o+�R��jŠ�р�<ArFg~�Bih�Ci�ᐼ�P�.n�`����Ў��Z̿$?��22�����\�T�����uVIԺ�m��A��*��і�3$aF�wz�I��w123_��"5��-��G��-�N%�~j;�%��`�,E�ٕ��/Pi�\�I��2R�H��KZI���AgU�Ԭ��[��f��a��*:����xڬ䅪����Ϫ�� YO�������EV��r"��#�.ܵ��3��RI���=9�t�Y����䴅�:�͉?V$j�6T�LX��:H����z2�-W%(\]x�Oq������8���)�'�}���«�,J[�����))<���m��	���M�]%�)N�R�{ &���O�����\\T���H�&�.n���Q�rq�R*%k��IYs�&�<�A��̺����}�y(�
�I�?�-��cT$	��#�yvG�}-xL����e�q�)R�ycgB���u���'�������e������>��b��21�Qy>!�	Dz�T�TABϣ1�
�A(6[�tv�$2?4Η�/���"����g�rtE]�T�4��($�t8P�1y��7�������J{��g<O=����7"�btK���0��q ��=�gR3�b��"�+�&r$�J�ȲLK�� ��!#�,MU���"�d�4���/`)R�>���m���JS����q,-w�܊�g^�X�|�0Ŗ!7���e7RʢI�Q4�Ƙ3���?N=k�2nz<v��BQyNz�T3��e�&\��j�ܠk�g(g�tC���;P�_�����Y�]B}�gC7���75��͛@�Jol���N~A�ƈ�S<}[,t6҉�j�B
\�3�#↾��*���4-�"�������BaޘNc�-)�d�\�ɠ^l�"��V�Iψy��P�����t���G��&�p0x���ab[׈�J(�����r7{RJ�4���C��|g�e�|�ǝ���܀��F��X��K8c�V���g��7�N�Wlg
�Z$�M�#)+�u���X�����nnVHu�lEi��o�C��ߩmjYY�["�Th
gH����nF۔���k��P@�Ec|W6F���!/F���%�2���ɳW�/�z��������ߴX�ʴû�c��_�=w���6[���/�����/�ӵ�����n��.=;�q��W�������V�E�����g?�����]��q�>@Ұ�eÍ�Tr� Z,1�2qI1#�]�O������v,�����YE݃�m��^��/N��(�"�M�t�Hn���(���=y�'��㱜`q���r�C�Z�Q������O�:#I%�4�-.H���2�{��ale�r|%j�v��s�y��� V��]!��^|��%s ���̘o��G�+DS�y��3C�r���^z��#y)щ�V"<&�X�|Q�?(]�9����2�o���\��c$~�vCE@��q��7��@��;��Y^ខ�`�����m11)���W)D���/ ���9b�-�#�E���'��c�4�J����T��Zq�G˯O�?a�]̱,�w����_w��?_������������c^�#}�xo�J���G�NS
z�K���rmnG�ј�^���l�Wp���3f����7aR�A/�ry+_n
*���'�c� rB~�E�ڙ���S8-�r���ȽK7�����	��i?,s���߿��a~0�]���O�޿��z�!m
8#$�>�ԭ��z�L���V%I (���x��������O��C��e]�a7[�J<�<	�??>�>^F�� �g�2�]�&�1�g>�C�#�� �F<J��Dh�|ǟ�9(���]*e럼>�5ӜH+?�2mG�|f��6'+՞���g�;��7N
�p{�����X=Z��*q��9Y��3�.LLFv�*� ���tܐR*<�l�9%<��o�G�U�W8=W�g�0о2��V>�GLu���4]��j#,cT1������!"�`��;K���y3+L���� dZ"���a��f�1yX�`'�(J�C�4��O����xc^�w8ǒ��n{����w��u��m�n�!h�3�/m�O�IepS�p���M�ڡ����?�ݤȀ��u��䅤��K�m��B�1v}�|�g�oA��g��0Q�^�u6�����]qh��F6�?b��=b�M��ю�GE*�����xm�3��͘Q���s��N�#Q��jj�Yt� ��1� ��*���D�)ьm�t�i���W}�z��MY��c��L�o�6ПJE�ч������![�^��U /1*�~4�տ��z�;<�JNtz&S~��~lb����_�'!����J���ӣ�Oݟ\"	��2�R^��b���Q�b�Pt�"�=m�!=���G��h��A�%���A�b�˕:Roj�f(<�넎�i�X�<	o<��P 3��4͛Dh�e����[�Wne�6�p��/�N|���R������]i���.B�]A/Wg� ����A9)���0�{O�cO\�����%��@=�e���Z!���c�f`F�����|v�>���˳Q�u`:$<��	�h?1���]����o���5H��>�՜+��W%]�T��kp��#1}�Y� uv=�āY�S��@���/^J1�D��%_8,���DF�D�O������,7����T�3���t�M":��EU�%���"�/�ue�����.�_"�����M�fMg>�͞'dDXn��#^��s|n:߭l���d���L�d��1�M��Yi�ނە��]K�X~�I���u�D_7/�4x��|��->�.xrw�ZA�˅K�w
�Ç��g2܆F����ǛGt�F���xT[��ǩ�{���5�7�N������o'�G�To0�������˚�Ju9�]-ԥ�u����eIAK�:XnZ�\=�n\=��_
�_�l��^@������h�v��d���t����@��,�%��P�̀���ȋ�*Zj����ؼ�� |���f�x�Q(S�sӮqbUS�b�q#6>�����~��m4�A؉�V�n����8����A���F��M*�7�r�,+zY��}�^]kɲ���W�� 7	�h����t���Q	'ӠZg��=q��pnq��k��W��jO�<�y&,ԛ���'f<�qF톁y�i/�O{%~�[�!��(�^1L�yEJ�gP߁YJ�����@�˲"F��ѥ�i���[?g/��hfm�\�q���#p��J��3q�=3G�'��=�QWOz
�תL]���>��~玐#c%{��ZU�+pƭf�'&N� :�ڡ�RC�J�����������n��9�}x��H���3��EZ�U�d�0�D���S�/�	7�5��@�������Gˎ.�쵌��������}I�����Kӱ-���;�cI�W��}�����v���DS�FFi4��(�� Ԡ��5��]h6�͆R�D���D��e	�Ӵ�6�!�ƅ��o���+k�ƀ�W]G��Y�!H�A�K�BSς�k�����
��$˫�xy!P��D̓a��2�?���ߖdݎV�����T.;r,k���eC�&%��*��盲O�0��~e�'jZ������u7�%����m�.�����%�
�Z�����=	�E5NF�umd�n\jӞ'�'#K��г�I2A� �2N+q�����<g�!���/ND�q�hC���o�U��\P'����G�G�.>��Ëݗ{G���u���ׯ���3�����ǌ�D>�>������}�]�+���S'���8C�K��"��ȏ�H�KW������-�ML��������әx0��У@mZ�0�����T)O�t���g�J2z�~ڬsVьj�1h5^�*D���*?\�������#o����G��g3f�������#� �.ʜN�@ӄ���,$UQ ���KU�9��:�R���JC|�eyKJ�:�L)\�V
��nS���ϔ���D���I���2��UY3���T-�<ߓ'�/���"���CI���Г~��!�Y���`@=�$~8�{�}*�y�-�������R��%I쉄&wm��U�T8�u�ậۺ�ۺ�ۺ�ۺ�ۺ�ۺ�ۺ�ۺ�ۺ�ۺ�ۺ�ۺ�ۺ�ۺ�ۺ�}��,� x  