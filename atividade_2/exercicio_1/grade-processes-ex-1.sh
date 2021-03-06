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
�      ��r�F�����H ś:�R([�h�EV�r%�"Â���2	0 h)>�g�a�������v�@W�"fz���n�(�b�=�?�b�@��١�ͽ���W��f{��l6ڻ���f���| ;_N��Ql� �����x����B��?�Q�E����O������&�&Uw�۱�+R�>�o�6g�����{ �հ������V�����?�����<}~�������_^t�7��F<���	
 ��P�(Pe�B���srv�.u� f0��,���S�Y3�C�?���CRa���XHf�VF��Q��dB��Z�H�	FN�3��F������'�j�����5{%<h��no/���������k���k���ۣ����(v��6<,�C��_ώ9#�*;�kvKCϏ!���x�{����NW��%{h�eD*�Of9ڂ��0��!�p�l2�l�Z�*�B����XR�	��-�]�[Z��-�7�^�	C|xS�w*˙4	kh�A�	
���*���>|A�wH��oT8��F��U!���M1� x� ,�1Nr@9
���:��NN*PF��G_��tP_���P
]�&#WZ$�
(�bz���͍d���,p��J�9TN�����됈'D��,��h�bh�^�9P��[���*���-Qᝡ��b����J�5�٬P荘or�J����_��R��%��h�Ym"�,�.�XOPlı'���&�X<���5� ����oيY}��j�K�꧱�F2If.R��0�@���{�CZ5e�\��F��Hmh�@d�_.{1���U}{T�{��pP��ࢱ^�,~m��L�뙗���K�^���,�^�?�Xg��L�s5��H��!��g�D�R)���A�=b�?�,v�o�}�O�9�+���������>��b|y�dd���T�Dp3�;�-�����Q�XG�_����&�B� �z� $m,��F>�����z����[�o���*��h��+�)V�o��L�^�T��|�aFij�N����Q�#�Bj�V���H[�D&��0d,�ߥ�ո�o}"��6�ɞ�>|Bt�0_�I���k:R�4a����W'�bS���ή��ɗ��8�>t��w����i����]y-���_��
B"X"�����B�\M]\4��Hl53E�1�H�{�����/��ꤪ���ruI��U�5��#���J�.e7��|D�ʉc�Mw«ӗ�����#�ƴt�B�F#@�k_v/2j�pQ�D;�w%��E����
$�T�D���������,�pNK{aH�K����I�~^�t��oMK��ύ���5yO����o�����"���m��M�vO�t��
��J?.=7k��2i�uG�h��|�zD��+r�c��X�j��`j�Wh&��l��m8��3��:������a�~4�J��؊�!�M�LmTEs�����"�8��3�Fg�I���
)rEr�D�� ��t������lt ����N��9p�[�GX��;G��#m�,��:Y�Q� %�Ne\�'�^�T�\O��]>吇�f��9;��p�9�H�L$�
��̓9�Dܭ���%-�����jv0
�D>�$ �3
�����͢H����3��,����yC���E+Hh�"�lH�Y3C�u��rוM�vk�D�'�h�O�7�aP��6A֖���15�F��3dO�s$�M�!%����� Z-���xx� �y�`�^-J<�d>Z$�g3��_(���/h�0̾��-�Uo,/^������f�wv���W�����1]�wO.�:�V�ɋW��b[���8}�)n�v���=��S�)P�@���Fx��������h�/=qO�_��i��h����3>bqQ�G�
D�
K������Rr�(.ς(���6��3��X4a��;��`:�I0��Z�F��e�����3"�+tr��I�+�/��khU,�T-���+���CHM�ɨ{S�+�6�|������YV�,�Nn1v��o���?�������/<;?:�^����2��s�P�w�շ�	��]苀�ы":uyQ�1���߯`�i4t��ɸ�9W���.J�4��S��[�bCH9��H1�"��b��R};	B���.��1o@����n(_!��fq�Θ*cS��u�=?�t�X�`�v��l�Ǐ������Т-o�0U�Pu��q�,��m�:�4�Jj<�&��ǜEly#B�*����N���̋p��~��� �$ �dd>��D�|yUa��;� �N:Z�4D��V9��31P���#������y��FF�������(���X��<V[>�ܞ�������?X(c$ha"v�Q�� F�Nva Ω�����*.5����R*�Ɔ�d��)�I}�"rF�u��C��x�=�Z����>%�K��#ܚ>�|#$�FT\t1���8�&gH�����c�]��a�Bє9�V�Ī]،�Z�Q�_o�8�$���zY�ɐ��o���X1�E������m�~����j���� ����մ��6V5�5tt�]{)c%�`@�qZ����`ÝPt���z�-�w��x�b�-�����ux���Y��-������SL�iq�@�B!��qDZ��ݲ��l/4y0���%`�hL�����f���	m-�?�3����¾�G�,�U�k�+��J2��Q�?�L�'�S8;���Glb��3B��(�.��5E6Dg�&����h:�������z3�U��P���U�6簗����RRk�W�}�U�P������I=�������|������_;�)��lT��6��Ѥ0��Ok�f�?�F1ƃ<]Im�&�,�E�0X���i���|����T���c�~�@\����dy���������؋1�HҊ��-A�-_��!=�ÍՑ�L�,�ʼ*Q�'.*��L�����,�X�T@�"��!h�����2RU�!E�/p<��X`2�X|�L/@x�.
�Zy�ڦлT+�{����h}����ǫ"�ڃfbL.�A�����O��6w<�Y4(d�W��9�>\h�`�� �2����GrDVk�>+���d�iWDZ3���]2ߛY�Z����#�����3�:"�a-�ع�/ݘq^�K���-��:�1"\��Aވ�C9�C9�C9�C9�C9�C+�t2Y P  