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
�      �=mW�8���_����!����]�.g)������I⧉�������s??��O�?vg�bK~IhKٽ�A����h4�F�ȍi�S�?Zy��R���>�k�)ӣf{������n�?j4[���Gd�۱��i;!!��1�v�r�y��GS������h���?�|���H���
��>�z����;j��_]of�}u���4����߼��<^9w��s'U޿�yspܳ_�t;�����ǽN�2�C2tǔ�Y�a��
!�B��#i��-��e��1�ɂJU�!��G>1^"i��c2����!A�ݘ4�����
�s&�3����������d!�5�q����Q�A�e�\�
����v�i��_��I8�������Ws����0��#=q��x:��(���h��f��w����s=/���*������� Ɣ�
�JQ\#}�Qb�9a�����I���C�T'#H���W���ơ�������'ԋ��Ѝiq:jL��!M�3�^��
���"�K+gb!y�!m��) ��i����I�F$�;�ĩg�����&�BOC�4y�M���0$�����F�4���ể����A�c�W�X}���3p��I�'�~�H��xB'��Ť�4j$r��Pv�e�@�Z1(�]Y!	{�e��¸	�0�U�uzڴm�Z��U�B����e�K@���n��6��dpV����٬�ꍩg2�,�$�Y�6Ϭ�[KҒJ����H�i�]�<	�m���̤%5�e��sL^��7y��0����wK�me���N��,'Q���$�a������C��Vr_]��F��HhE@(�_ONcrV5O��o;��l�_�ճ*�,�;=��_KVN����ɯ��U���d4)V�3\6>��Vs"f���ke\T�ge��}�SǛŝŔ&�[ _�'�YN���T��d�me���w��p4��ݒ�\�|X����b���y�@D^G�_��3�!	�!8��.紹U��ܤ�0�����\�F�@��>YIM�IJ�m�W^Kg1�|Ge����DͮG6�(5m��)r.)NU�SIE��jB�5!kf��M�)�ƻ��W�[-H�d*�'�+�-�f8*��O��̧æ}O�d����󓥳�����$c2��F�v_��_z�ý���r�}���W�ɡ��) )?D�5�w
�s���|:�	7Hb��9�9b��{
����/�8���D�����R�D*U&͹��n���!Z��0{� #4d'F�~0��N��ݟm��(C���t��BL�c����ݞ�A+�4,���h"G�]������{�$�5h�����v+SC�H:�9u�� ���ѴB�>���[>�������q(4֚L��]:�]!�$5C,S�ӗOʠIWOX��!k���t�c�3���K3���x��.�H��UސC���!WNĤCk�4����]+6DɎ�@�g_��4��I�o�����yb�&N�a�	���JmN�t�$*	'
�{w��obC��	)pMԄ��)�YZR�Wufe����S7�r�)�)�➣l�@�*A�:A�Hu1_'�2ƺ&��+�j��4P���Q��?;=}�-��p���fI�:y�x���K�]�)� ��r8��X���׉ܰM�PĜv����x�}E����qPd�d�����u������-���F�L��v��򮫚��Ғ�]���m��@)��6&]��1�B��3(Ox�ׄ�d��Zvl�3 �(���w���+�@��$�_"%=<�&>D��W�/hz���o�����3��+Ǎﮎ9��V��wm��x�����������c���Ao��Ъ��;�u���}pt����Zy�������sga���C�1d�A���$ +z��M��Je�F�=�Q�z���%1�%�y��Uvǃ�z����Ow�!�z O��i�g�V���O"$�|�J `�lO��q��|���'�i�)�ja;��y툾����7$�B��r�iD?�֙�\4S�������+(�N�ɞ��? ř��JNw�<��Q��.����Fo���JD��Ӿ���l��xe���fX��t"�[1.Y�q�6(�HdNI�Q�]��ǟ��V:�&0���`q�.TXQ
�A�x"jy��^>ן��ɤ���FrjR��B"�����������|:\>���r~?t+C��
�h��^���x�ͯOhxAû�c����������?���������^�>z�c�?����V��bz،��J@�0	n������:X|��{��J��̐�����0���X�[��Υ�#Y��7��8f^����������3����wa怿Jr�A�:�:c\����C� ��Xo�zws���?<y�d��i@Z8����4I}�	�#���jZ��������	 ��=VE�c\Z0M	�Դ,YI���_7Ϫ���=���-�k^��3���b�oI �L:��k���p�gt����e����m���D���Іp��5�!�[T+�V�׀ۙ�7�
��PMPԄ�c�5, �'�!���5�	F���U%����<��)R���"o�*�S�&��mh�sճ!��]Nrj<]nO�a5݀��$`,|CӣZ� �6�2�.���#�iL�#pj��K�Ҳz�&|vS< �V��]�,Z9]n4VV.�Y��E���)��ϧ�f���7��������t��������-���Vk#��j>�����Co@�Ķ��s����;zk��ǽ���?�?�v�	�:�3 ��P'�G�fKq;�ŋ���D����� S?S�hmU.}X�j�|�C��YX(�I��p�8l�l�5��<��Ay�	ۅ0�>����$�������(0>��lk$
h_Ǌb?�bh��1�o�E��[J���yd�#2�XB"�����݃V���/�=��3����I���q�9p,��5v�!v�����>eo�Í$\�9	6����⁆�9��l��l���kj��B�ڑ3	�T���F���4���j��ȅW���N=��ٱ��U��2�z��NU�Y���Cf5p������Uk�`j��J6�X|����Ι]�G�ҏ���p�Y�/��q\�����ʃw7i��/�?�۫��������{I3�i'�aٝ�^�:	Tg��M=�����2���42Z�Q��p�&5�G�x��{̷�5w%�'n	kE
�(p��������y洃#Xu�'d�=,��?��)6��:,ˊj2t2C����2j;��Q��C}w(�S�ǥ�OX�BFPA<�(4)�({��k;�%�9}e�`�a%��� |Y��JŢӘz���sS�r��T�?uO�N<�Csg�m��줢�5l��srO�y��5/�?��ʍ�G@������	�N2��<d��9��a� �~��1E`�&6�VA�uK�<��&�ո�B*	�s(c��g&�Y	�BI��+n�ʠD�Ú� p����H<��%,pP�П�G�'�s�f^�gF����=�Mb��Y��V��x�V��G���/F��V�5E3R��xN�ԥ�H�劭i��7���2/�
�I��P� ��7$��pdiT�!�FL�M�!�����A6�Z�--��hsb촘��*���
!Va	?��I��x��W8"Y�X�bV�R�V���a�,vDe%��4�E�&��<(N���\<�OH�y�C�<-tO�"�]�,5��va�Cm��"+"��z�˗������=(�V��آ��2����J�AM��y�10�l�Џ�7NH]�t.�\a���=��}<���d>hD�JX��q4Q��9�P�� L%�)��H�[�B�$[z�gĩ�5ᲊ�r&h���'�F��qYg`��dLJW��@h)A�h�YV2���1��
m@����_n[�����t��$�<�#]��x���������s\�A'��n��H���J�8%|qZ5Y�S|�nx������b	��Dn%{3��.x�q��i�<>>ocq&3�.�>������e���ã����n� ʽ	��D����4���>���ۻ��,i��_�	fN� P���&d,Ǘ6t	��#�o�7U��;�0�I{�x���T����ʘO��P���tF��m�CT�
[b���ɹ����nm!rA�~�^����ʪ �!U�{�E��%�]e�i�y ��d���i��~Ȇ�F-"O��~�9|e]qx��7�{ ����HU�f�#�qo���Q.0 "�����E�`*vC�{A#�2���z����N<�����EMA⫙,Cy�or9B���+B�x�s0[�RO@��'J��}��g��Ke8���'��O�9�/�����3��I��.Gd�]��1����
o(��[1�Yi�HP+��L����?���w�(b�LH��.��}6��2�Vm�ˋ�ۍ"ӫ��13X|�e�'gl����ϗ�5�j-���-��5���܀����/أ�x^#������h��b��UAju�����v��Z��x��H����|�=V��� �6^��Z�� ����p%���J�Q������	�3tJX�0ح����
j�w��N����"ݤ`Wސk����;� ��� ,L�)''JV�45�����#v91�L�>8@�IޫfW.?b+����4"j��&n^U�
��Fz�3����	�Ps]�D/:�ʞ`)�򊝆�?�����/:�������*���u�J:pj�uۊ �O����E���I5��������4Ew���E�g��-������*�|�	�j�_���dؚ=ND������]f�ޔ�H�~�ۆI�Z?�w냓ƙ�%�0>jx���g�j#P"ڽsY���[$��>gV�e�L�
�\B�x���2��X��?P��5�h�k�\���Tt��x�Ms��������{���ǽ����䘸,�O���+��eG�)���8&k�VQa���tqX����-r�~��!�NHmzͿ$d_Q��`i�4��5��~�������72�!;�t`���)E�^1vJө�$]Fc۵�S���^�_��a�<�NfA"�e8��,B��B&��'�����ʱf�`��oغ-~�D*�/"qs{�2�C�5�A�o͇�#%��(H'Jb�[
	�'Ӣ:��U�t�+m�q0���h�ŗd�A#��ԉ�R���^�̷Sd�>S}�$��A�y���H`Z3��AFi
��V���T�?��K����t�X>s8���Q�p*P��1����M�7KH���޼�Z/��{	K�̆aQ�:��u�k��'��&9�_s����l������}���ј�c��$r��N��Z��]��͉����:�/����{��B��|���[��n������GǛ�����y�#1�K������>�i�d���z����t�Y6*�t ����U������ߘ&�{��]� �0�%�j
B# �����凟�\v=1������� �p��H7y<�n�Xa
�ND�ڂ��j�:~ݸ��Z^��ނ���J��g_�s��jc��@C���0������1t6�k�o�ڞ^�^3{��b!�����/�;���k�r��{���9����b���G���v;�F�y��Aq^�ھ�M����}�Y�����s��m�ֲ����}������Oo�;{����Eۓ�j`fƤ�wȳ��!���������a���d��^�^�Q❭U��ȩ0TC���oM��8���yeK��`�m�Ƞq@dV��� �a��C������t]m��W�W428���v�'�ý`X���:^�A`liF;3~L���=g�r��}�ݪ�aB���h����������z�6���ky�Y�'��:J[=T ��4������,��bmkM��N��(N`+�	�Р�f?� �@#�Sdx":�������Y
ZDX؜v T?|������i~���6p1ǶP�"��`�Jf��卹"�tCa���E_t'�!�\MGW��;�������'�=�"�2t��)�A5x�1�m�
��X-��%K�j�4���%F�9p�YҠ:Y��굙::���t�VU��7N��NU������,Ģ��fN�����~�$��������������X���0���@�Q��� ��	Yp:�cf,���G]+��Ʒ�����oK8Ot�U�����K%\�V���j�:H�?��	���-.D�8�/� ���C���In,*�	�	�T���P��i��ҜTԎL����D�*^t����$�!��B�i>��VԐ�~蝌}�W;V� 6�W�ҵ�E���Z9X����Q��q��+���a�ə�W��&}��0HsK"&�mǋ�h������p������l�L��m���b�5��w5������8o�?��,��0i�E���:O�`	�g�qp��&��"���=��$��q����x�o󹯥����H��
�}i�����bR��vH�E�ј�t�#��ǻ[�ݍ���'������6�p����`�	Hr#Q�͒���1����WK�bq<5:U��9W��M^�g�{,%4��ue�^���=�H(W�-���3���5���좃6K�r�1����6Q�mu��M��I��=9��4�v�����S��X�#N9�2$r����>���C�m��[Z�1�O�q�⃗�1~���	�X��M���"��,f�=���VTl=�
�R�9HiK���==t�Pi6DWY�hg��9#2�E5\�T7$�(�������jt5���Q�9�MY���.��,�M狤b�"�s�B!�G��g_Ή2j��
N3��Z�y�^1$
�Uqh����f��pn�+bo��U`�ɣ6���_�]ȤiR�
��h��P
��o��Aծ�8t��zO�%���X�45o��)7�f�cQ�~3h�	a.!#��[���S�%�?�bww�u�d�>��l���F��VƆna�o�V%�W�U�0���ı����fa�2P���+!�nm�0����r-n�V��8�,�*;/.���S�	�K���K���R���ϤIx7���۱��e�V�'J}�
_��"��"�Bm�*�k���`��Ġе��\�\�raa[��w5*�����5K�
���6*s�H�Gν��3Q�O���d�o�/-��ӂrwf��۝��u˕4�͊V� bT��Qh�軽G[�#F3���-��F8�m��6���\�q��࿰"8*���b,��8#|G?�����"�����E?�����C��y��x��[n�]J0�_oo��`k���p���[���ǔ�,V]��H�:�;���`�?����,������m<ͮ�=�0M�K�}#�fRJyϒ�����pvn�4�7�ݺ�7I#6xy����6o��]�(��H�m�U<�a@§�8P��@� y�nCr?�C��!E�c�F��f2΁�͑�>72z�k�@rO��@�纓���~��t��7��\N������0[d�y^�����;_��E90hm��x��s��v�sOG�X��&r\�g*+������]i����R�М���Z?[���l}�����.\�ry�X�b]ӧ��J��C���?�r���?т��0��&�Zy̵o�7���������ã��l�9*ay���c�cÑ�{�� �}ϝx�tt2K�o	��<:���tS��(�I�R3o�YS��W�:z��
����ۊ�;��>��J�T����jm��3�L��e����j,�n6��ZA����v�	�{��G{W˅B��!��p�`�9��w��Й�;J�I�/�������21$2�cx�es� |m� TU��)�p�e�����b��S��\�Z������ܗ)vjo������k�š�ق��cV6{�̋ �ŕ�"��P�4�Hc�	*
U�N�� 5*{4u ���M]Zi�d��ǹ�1�y����T�ܯ��ԟ`�06��{g3/a�1�{[tVᲖ�n8o���e��Ku$���S3k� �y	ۦ�:&&A%����+��0��=�4��w)�5�52s*�1T�Aڲ�m3g6���TsJ���sdU~~��U��&�8<PJg_P�P��_�XJg�:!R���C�[RI��{ G����Е�?��ƽ��9�d��$=���+��9l��n��G��c����͍<�S0|�04y���n	}��`T	�J�:h|ܯ3��H��	
��LTc��x��d23�cK�ف��\m0-"- �%L����/�}������f��˶$���u�5�ا��*���W;�dtbǿc�����n�ܩJr�hGnm��ʰ�?�a%_\A�3Y��U�x���h{����Z�l��� �[��$���+4����sx�
���
�ŗ4p]�	`/�F�T�\�LEh������#��XQR^:+�7�Y%�~�_�����������������w
�"��V�|K�&(i���'%�[ejJ�^doZԼt��g���U'�iA�z�<�e\���ۛy�����U� ����Մo������v���:�KOۖ���$O�����O�IX
��<(�	�Y���됤B�����t�W;�����B�ږ��B���xTa������V	�ʩʣ�?J
����4��Msy���o�t�Ӫ�t����N��J�����tEl��$��ď� a�8ff4�u"$@��9��Џ_�oD��-fs���^��%"�}�D_hK����<bK�u&�Z3b+�Z�]˻if+ ?r0�H��z.�<��Lߩ'��\#w!2\��\ݥ���9���c?�s�����>`֫�?�Z��,q�������'��=y�>ޮ�3�m>[��.cW83l��!|��]��r��E�4u���J�ݍ�I��rW��%�5o��Žh���J�V���K�r��1��k�lgs�@�RF/�������A�[���,�Qeu+��f��^wḀi���x�eQ�u��4t�0�44[6Y��(T�v1gY����,L�J��ޚ��)ď���fz��.�< ��^��Sα�i�ʍ[ 1��Ƌ4�?E\� �d"'�;z����y#L��$�.��S�(��4��/�]t_ ��B�ma��"ŕ$fwdTe�zOƏ�Z ��T��M��D�0U�ĆO&ˋ��+��_响��1�ؕ(E��O��=U��i�?�t�_-a�"J|,<�h�e��%�ʉ��������x�9)��p��5��B:��ٍ�����L�@o�{L�(�;7s��v
��5�r�;&�F�t�]�T�qF!�0����zH8�%���Tg��"�*�{#��u{>�Bo����'��*�p�ĲEDI�P?*��8��-�>�\!ME��Y���N��)����+\�
�/h��"y�g�[/ˆ3��{T:}H~.��������10���1ae�����a�W���_*	g8[��l���w�a�7J[�EɎ��`�4S�$|���G�HM��Տ@�y��s,/+;�h>N53~�*��!�\2K��'�^�ݹˠ��R��>KrjT�����6�����UFӢ@�������H��x�HϞ��^cd��W
K+�S
�
�X�Q��+����9��m.λf.���i@��g�!Y4�����
�����X��c����K<Gj�l��mo��<����I�G/�	Y��ܪH8��f�ʕ
�GďfΡ[��=o�7�o켸	&�t���2UdA��Â���mN+�#聳�G����&ם�.}1@#�?��,���A��s�1�y[�弫vsx��.k��5�������qq�V�L�#Sj���T�p�U,�F�J�[!6� ��p�vx�5�?F�|��e~�N�_)�W� ���	�rNr��\xF�\R/�#vU�s_e����H�����et�0�Q��A�2�]�n����W��� �XĴe�GC���c���mbv��$H*���*�Bl����z�&(a��Q�%��~G#LE���4��b W5�HщF=ӞphV�kf� ��hF�lx��(8����:q��R;sv��A� g�Ι���D�P%,+	_����h*�}yL[����ڽ�a�`�9(� 䜿�*֯,M��q���}i�xc�n|�b�XT؜+j�p�;���\Ԃ���n�C�-
�w�8���^�u�J�a|3�,��C�F��K�ٗ��/s��Nժ�X��ꚥ�U��+��Y����=8@f�$�z�1�BU�X�w*�Re�7�\�v�����Oݡv#m������j�����Gw������w4����A��F	�ʾqpRp�_޽b줓��n/_8R@Mo/h��LR�M�0�6�STF�'�*'��ؐm�
\�I�EZ�S���Al |���|)��5M ��	�;�=WPē� S�j3Ur�\f��ذ2�����G��ʄ �LÖ��)9>�>=�Ϯ4f�ܑ���*����pP�ʒ̋��☳ׁ�desĹ?�Ѭ8��-�/���F�yW��sx�Kc�)^�o����W~{��|w��<�W����]���dP3��T�YY�r�%��������qpv�Z�B�!��L���JP\r$g�Ds-���a�I��dk���T�8���Ӆ�0��Q&c2����_��v��=f��<�B����f��U�m���!r���)tt����66�l �,kY���e���A�����kZ�l�޾
^w�e�Ꚛ\��z�l0��%��SW�p��&'�k�"|�v_���k����
�������q�5@m�E�i�&(�c��B�^:�$.��p���Q���X�?���V�Y��o惎�e�?��8r�r}�����^y�+�#��\W֐��F#���j��EO�*��!I�ߋ�ڏ��9����,�Wb`nE���lnx��P�����zq��(���v�#v�m�������ՕO����xp��|z��:���8���$��6J�����}�|����g�q��`2��wQ�֏k���|\��S?Nn��S6�?�t�Qf�g�n��ʣ�=|�� �tL�;�6��BP�Gߑ�N��u$�2��Ķ^�i7*�"��i~��
���Q*�&^x�t��;Ffc��,+3a�mPE����ۋφm�J�F�\��Y���/<�Vՙ{1G�Opc�6�f'c�ĳ��Œ�C�e������^���0�0#�Rz�g�EobL�H�<?ׂ�@~�IT�6��6�Nf��/���˗�G�G^	F�W���!�m�敒i8m�R�%��H��i�4����pY�-�;��%���ϴ6'��Ŝ[1��?i2�o�=��a�<����*���M7{+L\wE0�F���d��Z9Z��Ѫ��t�e�P<�����������s=�X��6FS2u��>Q���:��Ø��m��/<�\������/�p�/Xhhb֓�g���p$~�{ �4����� �3g���� �۔��
R�Ǽ�%�#l^?:�k��i�`�3[���5�O]:��۵���-X�2y8�T����,��{=r�ŉO�K�G��s���d�G�C�f�iW?C�(Y���/��M#��6�y?W�yh.���MР+��k^�\������r}0����E��f*�4�~�%d�����"|�����xM���4��&7N��z*\���Yr$��Q̀��,��+��l, L��.�#z��!N0�~�Š�=��P�ۥc���yHK��Rp�u��V4M�TJ0\��Ô6W���� �:4	Jp��>�4a�v�Q��ґ�x,$�J�R�ʊ���̋i�3���d��#������%�ǶIס�6��R����:F�,��%&3���Ok�~�� ʏ=�J�>������2��j���i��l)��T:�!�����-G84�"1�6ǾΦY�i�*�&��M�����w����Tj��=y�g��,j�����;��6���� �x�yMܶF��y���л*�Y���S�'�(��0+$�Qԙxo}V���������:���)���^f5֭�'���[W��mvJR�~vB�-���V	Xj�����WN�4{���H�E��t�"�Q�ⱷ�6�'��4{_�@�-�����4�5�x�+.�&��C��)0���1#k�z��&I�k���*tCQ�v�ܗ5�c�Qa�����	���!�˄<��l�/.pl}:]O���U�ʮ���CE�nH��A������d� he%��Q���}L��sCS>_�)��>y�Yf�w�������8t����!�aPyR��u{���Xw��Z�zY�ޮZo��^貭����`�x�t����>��Kq�(ts'��iA���@�%o�p��Yx��S��V፳�]��UXFD�'[��ÇM��+P}�~��5fJ�#�/޾&-�{~@��
�kn�b"La������&���Kgz�KD�ۇ��P����an�&h7�e�̓¶�������X�	ı[ޥ9k)+q�z��sT��z�&o��|�	ph7�Q�Ԭ~J\�5�J]��Ɗsץ�)�+oL�B�_'�ÚK+�}G�ղbz�YA��5ь�)Y$M�l��L�1��]�tM�G }K�JaD����"b�-�1��vv�I�i2���~�wEd��U�V�n'�\}iD���{F�f_�t�����f��(�Wʠm�@��BM�e���8I̅k� ��F�Z:M��Q�����s��N��|����5I'�u�qh��N�v'�:Mgic� S.���lE�as�,-Dy����V�J	]�$��9G�/J����,�Z�6#�Q�P4a�D����ZX���su�N���[/��ß ����hm���0���v���F�K�m��m��Mﻓ�5��4��K�s.�����C�������(��V�=^���~�g�����uOC:[�����o�����������Z��]�9#���Zp�� ����Q���^z�^7k�(�%H�L� 9��F0k�Ռ]��j�\jm�ġfz
k�;_���Զ�����>ZGW�v�����]�_���xSF�3/H�r����DXtGP
�F b8�]r��ć�>�$�&���k�v!�B� ��`5NcH ܃��T�&�.��S?(uH��DN�8�� ����M�:௫_`�b�GW�">�q`f�xⱝ�����4BxH��S��9�_܃�Ρ#�wʞ��t��C|�o�I��	 �����F���х�QǛ�Q�S.��9�C���������;F�ngoo�s �FNf�x�[lu�GlȆ^��H��X}hB�l�
F��荟F5ƁG닍w h��#������7������1Uz��q'�iּ�ض@"Q�A�O(�aգ�D.1PDe������}�ڝ��z��p��&c��U��p������Í6�VqL'Ȏ0�#��-נ#S/Mf'IJ� k��R7�y_ut^#+L=����)�%mhx�̮~F><b��1�Ѧj�������-�E:S�؀���9l�����9-|s�q0x���������=�R"Ǜ����z팆 �ȿa��������[�X�?@�W"�_ z�Ğ7�?�.tƣ1�0�C�m��������������&���>}�j���wAX��d��u�
���2�d��J�<�:p�MN/�=3!>����`o٩���5�1+JIkV���N:�9�%s�C>C�����#8��V`�-6̑m"���7�v�N��Š���}%�=䄥��5��ˆlN���&��gG�x����M�w� I�ߊI|��Y~�	
�	��4W�5AH����S��Jfo�7g�f�{������a3z+�k��z�#�tK�%z�Hd#�L�޸˶���ٿP������5�y�����=����;���}x��M�xK� ��(���!�/\���ץ[�d6A�r(ҩ�%�Q�C3���*bh���/��uQ�3�E����:���Q
�QD<b`�i�h�>���눜�@�5�+���_�0�>֡q��c_��0PW��`C�I�(�c��#��v[�!<�������?�i�	����~�����"̺w�f�F�E:�I]SǐX��󍽯v67:8���!���2h(f�b:��e���'���v� Ɣ5��)(��:b77�2�J�ND@�ak��|W�w/Q|��b���\�E��k@:>�$�i�m�dc���)���M��'e�v
KG:Z��)p٢�����Nv ?�ݛ\`�5}G�MO'�����8���~AA: U�'��8�c]]���^���(�)Z�0�(�x���sd��*Cu�x�\!_��{��LS�59���~��%ӻ�X�!�v�,���X%���k5C�b��6%�{g�a9�ke��pe�}���]���.������Ss�@Ĩ�D�o� 	]i�j�j�V��%�N���W`\=y����l\	,,����#���ף�(���^��EN�4�7	������5���\i�.<M��wu��N#4Ն��Ɯ��/<��:]�w���#'AH5äFp�c<��.k��M�;B�̀B�����}�R��3��C�m����b�k, ؞�i�4�� �d��R��X6���>��>_F��@)�����lEMS}��w�7w�_��u��*�7Tcp~��}A'��P���M,B*�5�	��O�U���HA�J�*�f��*�TxQC>�����a���o�_�{��{��{����<�B�ӊ @ 