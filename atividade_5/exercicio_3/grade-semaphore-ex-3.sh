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
�      �=�v۶����@'!e�և'v�ֵ�ԧ�������]Z�l�H$CRq���g�_�}�� $�%9��v�'����`0��(>���b����Z�6�����Xo�O��iw׻��k���oZ��Zk����XJ�,����o�	��F�p�����8����'�Wт������]��J���e����Ʈ��Ps����v������n����߼���[=s��3'���}��j�h`?�����ڵ�{���vm�l�N8s=����5��1;fK�=k��-_p�d�=��%�j�1>���Ig�<?fc��
���6��]�@�@Q=g*83�Ň!Ò�bʨ6[Jp�%l��h�{~�I��]��U�Z���Ns����F��1�z����~�0��[����m���7��F�}�#�_�xVӳB�;��&�Y6/���#f�\/f�G{�OS&�q������0��lx�u ��j�'wF6AS��@� &�P�򆀪3�b����r/�.C7��udQc�qi긞�?��|�T/,���r&�{=�U��`*�ƛ�9��A���L�xF��N�6��xz�-r�j�`��!뱖�G>X=�g�����7XDR��Ⱦ�7���L��QP
\�&9VJ�I�����)�F<6&Ŭ�`��+�Ǫ�,� J�����˙>�6HÀVq���I۶�j��V)p�ON:[�(W�v%(��P�l@�Ip�ЙL���n��M�gC[V�ԯ�S+�֊����Y]$ж�.]��6��OfҒ�3,�f^��7E��0���7K�k囟�N�ɔ�(LAS�0eF���]ҡ�RM+���HE#�r��& ��/�'1;���N������O��i]d�坜�ůe� ғ����N���I2�4+��U֫�=������Z���3�̲�~��>N��͂��"����W�}Z��3}:|]٧��]�/'�o�ŏnI�./|X����b���~I 2���/�n�TcH�N��� 8moUp�9W)+�а��Kn�	�Ԥ��T����,f�oY��ݹ�HT��z�`��R�v��"�ǩʃzj�H4_Mʳ!eM�LR�k����x��W�Z��<�L�����%Вl�щ$|b�'���k�M��>�OVΦp���ϑ�I���{�a��v�����A����AT^�?$���� ��	6�)liΩ` �����t ��vƉ-�H���@���Gxi���^'z��'KlK�TI���ݸ%Pgc�"c? {� #4T'F��3�y�G��O6HQ�!��
�Y:�/�B�'���G�A�!�V�yXf}�D�ػ��C�,g$�,�n@C,�,-�[I�&��Ե�'~��FH�
�DS?o��@ؗ��J,.�Ʊ�Xk�;�l2�]!��4C.S��.��A�����{cj�)�t�#�I���ʘ��x2�.�.�I��Uݐ����a�NDR��5`��i��]k6Dˎ4�@�g���,��$4������Yb��N<��z(S�Uڜ��d	HTN���-1���Ć�UR���	)�[^���ufu���g���37�#v�)�)�㞣j�H�*A��:A�)u����j��s@�J�ڂ�u@�:J?�!�����G�b����#Ь#	�d�Z��
p	��=)�cD;]	�6�+��Y"W��Y��X��!Ԋ�`BȣH�@^�u��?Uca�����"V�дE6�%ۈ��˺ٮ�W�uu�]^������Ҿn#(%���Ɣ�%�%bL���y�	�Ś0�lKr�ȏ�f@S �U�.]�y�d�<E0�WHI�2"�ʳW�/hz��گ�����3��KǍo����N��w}�ݺ�����������c����`��ԩ��9���⇽x𢷴V{�������Soi���Ú3�T��~��% �#�a՛M&��čb{ģ!�F.|����gVٝ�B���L�/�>�Q�5�<�����Zq|�#?�����+,�ų=y�'��.1,N"�<�R���v w��}YT�oH���#��҈�gKԙ�\4�p�%�rxEn��=K�ɞ��8 ř��JNw�<_�Q�ǿ>�	��)���Go���J�fS������bH�x%�Krs,/d:�صW���
���s�tte�0��ǿ��N�	�t)X��6�VBe� �2��Z^��������F2)oi�����R>����.��������(�o1!VƋ�?9�����X�2Z�ߧ׿}*��A�S���&�X4�w7�����kw�?���������n�>|3��i��{�V���q8C�&��"��I�p�����k�`�k4t��dƜ�Μ�y�4n�J]��<�_j	.m\��l���&1mx��6�C�s?f��%�0}�S4���������MXuƸ2�>��{�>���`���y���������M���3f�c�f��&�^pg��V�J t�$5���& �v���q'��d�
v�mY��"ǿl��71 z ���LpעJ%,&����ͷ$ k.m�5���N8E�s:P{��6���~���J}"c�{#Іp��i!w��T��ՙ� ws�o�
��PM��D�c�5, �'�!{���\�b#[W��X�@:R��ˇEK�P��6��7a#@��K��:��&v9ى�`�3>1�j�W�$`,}C��A�mHe]�G��G ��!"pb��pi����>�)����f�=�VOVZ����G���eE���)���f�f�����w�߷�����Lܑ�a3�[���:���:��b�g�}���F�3����������=�~���h�h۵�u��@d�C��1�,�� ����D����� 3{�(��ڪ}�a=���s����B5Of荧q���V�A�9�gg���ᦴaN|�Q��4�è����$(0>ƴ5|�Ŋb?��4���7�"�܃�-%U��f�<2*��M� �h�=����
+�\n���ӹܣ��S�����#���g�<��"ޣ�;��V8�H���I�1��b�n�xc��5��3�]3#�:��9�`�+�A��@���^��*C�3��3Ϧ=;j�Y�ߖIG��:U��5Z����	#~�.��F�4Օl�Q|����Ι_�#k�x�.r۔E�Ž8���J�S_�s�n&͟�o�����Za�g�}w��V��iډ`X�_v'�����Nՙd�f��ټ�_�0?E�hd2�F��j�;"|��x����Αؾθ+�?u�H8S��כ��wHa���`N�?�U��	B6��R�����i)0�bCn>�g�UQC�N�H �ѫ�������79�~�T�}�"r�
��BSb��������h��Đ%��JV!�,��j�V�X�4f�<*��T�\0+��OGݓ���ȸ�g6�y	vRѩ���9�'�ۍ�@����Пy�V�*�G@N�=SS� �u�)8/�!Cu�d������Kd�);2b�m��4�[�A�H��u�RI��X@�F13�N%d��(7)VܼUA��CM#�>x'
����U�	D��q\:wn�|j�*����S�dF��eHi�N�n�)y$�X�bT�ke=��4#��P8�2+�D��+���2_}��Oʼ�+�'��*Be��辡`@���(C%ri�d֠eb��0�k�M�VWeK�dE+ۜ�L�iue�煐�k�������cl<��+��_�\1��	c)h'��0�)�����N�k�	���S�%������i�OE螗	ݓ�e<�i�(��L\�4O���FQQ1v�D=���mQ�ʖ�=(�V��آ��*��'�J��AM��){�10�l�Џ�WN�]�t>������{�z�D�3*X�8|ЈLU�����\Ĭ/h���	@*��N焣�o5��d�<'N}�	WU�V[p0A�G>1�{U����1%��p�BGJG[MY���Ɣ�+�%�b�(�j�J�F!�?��J�B�x�tN�j.������*�b�NV��z�H��d�c��8���� _�+Q��x���0��{Z!�����\x	"5҃4g���8�U���S���c�������ppx���`��voB�Fs�,:���|��N�"��&v<+Z���r�Y�( ���Ű	+���=�#j>o���3w�a =���~%0,.�v����5���O��P���e�RdLT�r���M����-3Sp�,֕����%��{ђ��+� ��T����?W�gt���%��>�����E�P�F=D����}��*���v�9n��wA� $[g���̾E��������\` D���d����T����.�������@��x��9���$V3y���_r��i��W>�T��c{�\���`�O����%����pꇱ�?��s&_*?��/
g����]�����@W�\`LF�xC9ߚA�K�B�2@Xh�g��\����Am�c�@��`�@Z1vAH?����d[3#\]�}�*3�ډ���/;>>��_2�m?Y�6X�����g��i7��J{��W�<�G�����V6���c���G��>�kk���J� ݕ��>��w��d�H�����cz��G� �7��c�sUr��L�ѯ���֪,m�KN��V�:%��0�V����
z�N�j���<ݤ�+oȵKy�����܀��i<���=��Bɪ�f�z4�6�.'����uR�����{l�h���l+#��,n�U1N�+h�W�q0S7�=�'�C���%z�1uz
��@��+w����8�����?qx{��[��qwNSIn�� ��a[� ���0t�(p0�]L�-���LSv��l�_�z�.m	�����չkOhV[�jW~'����DԺ�[�/�2��4G"��l�0�W�G�n}p�:տd�&F��!�8A��]oJ$s�\毹��`2�3+�}�o(.�V<J���L�:V���<t@M�.��Z��7�t*;�O<o����Ǐ���������[Ie��1qU�_�Vq��e/8��
�㈭�;e���}:��C��-v"q��!�N�m�Q|IȾ��;x�҂i�1�B?�d�!X��7r�!�8��*cX�S��$v*�I�I�Ml�FO�A�������y�$�<�D2�
��h����+�O.CkmUc�#A��oع.~�D*�/"qu}�*�C�Gd��6��PՇ�t�$������ 2Q�LTP�J�w��"�rNf\P|In���Ν��B%dwf��"�\�-�<�;E)��_D�Ԛ��rJSj�r$T�"��7\�Į7����I��`jD%éD���Ƙ�^�3�7�ٮ �o��j�l��$,0ò�W}�����2�O{M��L���Z������������>��1��Y�F1�:�����>��S~�b�u"�_�)���������3�j��Ag�ߵ�6{K��^���{f�K�����>d`�f?�p�_қ��@3�j4j�t ���U�����ߘ'�{��]�$�0�%�jJBK# ������凟2�t=1�S���H�� �8�o���I�M��wA�0sgx��ƒY ��&~ݸ��Z%^��\��ۉN�ç��9�;��������j"�=�}vx�-�Z�[��넗�W����f��G�/�����m�9��?��t~z��W�G{?�;����;�^��z�z�_D\�v����b����x�i��������������;��l��j�����n��_/�h{vO@��ܘ��y><D9Tq�Щ�,�k�g^yQ�%e��9JC��*�09�nht���[��1�4t^��y6� �D�"*h���z���6Ltx�><������m��ѯ�'=lo��봎�$�׎����n:4E�lDR%)�M��O{v��O=����<H rTw�+���"��`0� 3�ab��~{�mG���~�q���G�_�@�
8 �.�+w(�&��l�|�C�,�����u�Ӯ�Y\�u�U�)✉����BH��4-"(mN
��3i?8>>Q͏��W-\����-�
oa����*�G�c�HXf(�%ذ���J��5ę�2t�+~�-�B(?�1F�����X	��S�OA	��cf�aKCT��ž�ZX��4�6�W3����Q<d�����-���Q��5SG�	1K�Qm�>j��"S�l"J"y6�l��O�_���駏s�`�_���I1��+VSZ�F�s'�]x�)�8'@�qB���؆Y���}q��i�8��jx�����1����,��V�ElM+ৢ?;���a�:�(��<{�Q$"����զ�ǐ/?I\�Js�K��"�j@Jv/81,�HE)d���RW� �N� y�4x:L�a�4����u�l�r'��JرZ�ɢ���%/"Uu����l̠�/J�=�<b%Z&H59��Yu1�I߸?��	�vz���1�;73��>|Ec��`j�}p�I-u����/�}1m��J��&i��'�U�͋�O�`	�g�}t�? J|"���=c�,�	w�D���O����s_J��N|�im�0�O�4ѶE-�l~I���R�Qg4�>YH�����p������b��ٶ�X��rIf$��i���}F�~�jb��XO�N�h���s�E��b��̺��,��ʈ=3O(��-��-�ѣ��5���좃:K�z�1������m3�@-�(u	���?�ԏv�
�L5)F�C���L9����� �&�܋�Շ���m�ԌA�����/�$��-�+l_L`oG�ķ�c0����B$3��s��+h%k@�-{Va,%�A"H]�5��ɮ[�@���]e�����s�g��j��e�HIFq���SwH���A|9s����e�T�J�k`2k����d��k�W -83)2�B����L�D5xj��?[o��<K�%��9���gν��'�9tE�m��jI ֌<�C�m�ڥL��5��;��|�R�~�~����P��Z(�TX2��`�Ġf�@�i��i.,��o�BR!�$drM�+���Y��I�;�'���d�>��l���F��NƆ�pz
��V-�W�U�0f�k�c%�)�K:���d�x[�+!��m�0��vj?.Z�鶂.��aU٩{q�̾�"�M�]���Jo8��)����\W�3��|t7��fU�u�J@���l�L/�	�T���j`�>�R�F�4 ���P��iU.����ʳ�F���R���A��)[Cpmf��B��'�v̶3Q���^i3��m���d��"bO+��3�_��z~([���2V�-,�Q9 G�C$@������BG�f�QɎ ���wH'kcw�|hꍱ/������-�*��3�7���>_�: 2�{���_�UGl�?z�?�O��~�h�)�������NN��6��h�|S2_	܊d`$G����yQp� �]�|�1	�5����7�����ͿG!�)R}��1"&�$��<)T��M�=7��6V��in]8ȫ���>�~�?�mӡc�+/e�i�����
$,�ǁ�%b{��&M��4t]D���ƍv��d�)�#g-s=	ҭ�Er����6���v5�̥�N71��q�A͉���;���	�K���2����oQ|���L�����q��^:�.���X�U���TV%�=���t)
3Ǥء9�ۛBh��O���ַ��r�9�b�\B�KZ,k�4�Xi�sh����T�nJ�O��d;�5��� �Ts���č6���|<�y}|��ׁ�S����9F96��lw���&��Ϧq�-�z�'�����f���AUɒ�d�Z�~)З?�od;��M�U����.	\va�����������'L���G�U�L5o[���R+(3z��=�6��c�!��z�w�B(�{r2�	&�S����m�:�x'�By���g*n�e�Z`9�ԛ}x�eV3� |�� TUS�S��f���:���̜2́�ZFTkD�4�K7M��P{#v=���:�Y�4[�V�ʦ��ED���T�*����E���&n�1�L(tTE;��Ԩ�H� (o,YZI�d��Ǹ�1�y��הT��o����1M�vqu�틩�0���#:��Q�n8��n۲Ȋ��:�K�S���7������P�
� ���YEP�+e٘�ƞy0��w)�%�%2s*�>T�A�2�m5g6��cTs*����r���,]���Lf<PIg_P�� #3�����tuB����[�R�⣌d|r�JY�hM��]n��Ƒ�KF�����C�͸
��æ�H}�?1���H;�(�=%Ç�AKÎp��`�����s�*�E�@bi�����6Ê%�i���dl�伲��W��-$��9[��tE�j�jI��/am���Vv��kLҽB��Y�����#	ӼE�{U�y��Kѫ�]��hĎ�-�.ӳ�?7cgNUR`Er3HuP�����+�V�J<���Zf������+���9�n��߀��σ>{`����z������Z�(;�3T�ϔG�.>���L {Z��r
�3�2%�W�����X�4��tV8o��Z,����"�����쀌�e�������e�ʪ�k~$5J*��?����65S�^fojԼ6�C�X�od��`ZP�^�'Ռ��T���b����nUg��-LMն�ݣ��s=K=N�q��{e�m�v���)�}�8a�=	+!��r���Ŭ�MR��a���K7��E/rp��������l31Uد���*�]9U{�G�aI���Q�)v�\�h|�|I�lZU�N	��=�RyY�t�>W������a<�}7����p�:̨�u"$@��×ЏߔoD��-��:�@t�N����/�%T���>����H�)�E��x��n��
�{��٬ˠdVgӨ'��)\��B�&g��k�	�s��?r�n�*�V��}8ĬW��A�U;NqW��(����N,��;���.�3�l>�[��[�&w$f�*NC���oY���/mZŒ�~�(��4&���}麖�Cע�V��"E��-����X����<�a|s���M���J�Xj�2��123��(�s��L��x�55_�[k���j�b>�X����;��#��]w�LC��HC�U�UՃ���.��<T� q���T)c��譙y�B��X�0���d)��!�1��E\�96>oչ�c"��ݐx��������]�LH���D/q�$�B5{�)۽����A����&�}eGx���� }���h�v$O�L�;2�2��'㽶��Tj^ܖ}ɉ�a��>�,/�K�lf���l���ƮD)�e):�,�ZT�9���1�Z��e��Xx2�I�1+��:ٳ��1-Z�x�)��p��-��F:��ٍ����MM�@o�{�M�(�'7K3��z
��5����>��#YG�T*ժ�Q *(����8 �B��n���L���^�1zg]Ǟ���ƛgS
����KU;~h��"��L��X�uv��-�{��B(�?�Tfq"v���BN榮؂�P��~�Q&��l1�eyw&�G�Ӈ�G��J��� ��*���܄�rF[.�
����/^m���I8e��!�d��})܉���ɕ��y������i6yA����_ ~�Bj�����WƱ����F�qf�1�/P�qr�M���;�]/��|ˠ����y�$Ԩ9	���qL_vXP�ה�~�M��CD�i�
2S�"���3Dr���#ݵ��[Z9�J(uF��0]�$�]�y�n3q�-s���Lz�~��Es	j�ŧu8���sc5Z�*.��-28�;��>M���$�>�8'`9�krkF��X�0�O]�� |D����Sn����p���ޫy0!��L,X���&J >���"8�Ď�g��B)�M�;K.}����C�Y=��\1|ёc5�f'���`�c��Ok�����qq��ژ'M�ž�$��E�ri���5|�K����ӷ`�3�B��H����,�y��7��U4 �]U��h� 9q�p.�Ѩ��K<Į���7��qrJ$D����2:}�0H\/B��w7��cX�����z�5��ELZ��+b�������ND��xT�WxT̅�$������&(a��a�#��~�#LE�N�$
/" W=�HQ��9Ӟ�Ь��ܘ����s��Ȼy�]���4x����SNDP;(��3��9)��������#�*f_Ӗb��j�^ŰP0�m
⯨��K��2>f^2��U��iƧ�7ΈE�ù�V��|cuN��ZP�U�M|��Ei�w#�˪.��>,��z��|�و�~�n�u�^�.s���*}^`��?�,M��[nc���vV�v
���XRl=恨�B�*_���TeOo�.�v���l��/�Cm.mT���������ɓ?-����b��w4����Q��J�ʾ�wVr�_ѽb,���I���)���+���0�T�M�8�K��R�>IV9��Łl�T�JNb���N�0�Ii����zՇ靽�	�;�&c/�~x�
�x�@`J[Ic�J��a���&nlhq7��NC��ΙeB�&�b���)9>�{�Ϯ4f�ܐ�B�*����pP�ʒ̫��꘳׀C�����C�" ��<Z4_Be�&������l��.�GS����� \���ʯ���W���I)��W����W�������RCˊ��3F(���g�'�茼��D3�n�w��+ūť@r�^A���%Q��?�<Ii?���w�J�r�"���&^�ɘ�wY�����z��f��>�";����Z��-:d�* r��)tr��
C��;Q�r��5��K�ǲ[x�3� M���ĳ4b�xo�����c�˜}�jr9z����0u��a�Nݔ��':!8i?\Ð��p�� �L�Nѽ� -1�V:T-V��-�;��`/,K�M,P�ǂE:{��Kq�f��o��X��~ސ���s�G{�l��O7��|�qc�O�'�ܰ\��ڼ]}W^��5ő�ne֐��D#��-��ѝ��2��֣Gl$%~/cX�<v����+�yf���܊2��9�,ǡ:*�-�ӿ��^�d�n���q2�6*�?,�����O��]�l�1�n�`�mT��������b�����Ԣ�6�d����Q<'�j����In�u!�樂�����)U��l��{�P����х�a���k�*��{JI�\������+�C����i�o���Ь"K�������Ũ1����\�m^x�PT�;��Ơ�4+��y"��&�6���C�{�MV�"��|oЦ����7h5#7���(�P�	�����%�=B���s�j���-`�/Rs�a�v�=S� �-�o��;�Lὃ�%оl��7+�+����i|�����}�oZ�Կ�d0@?�SA�	Fd�����Q��b��E�э�S�WX{�!g���J��
����L-��f>�;�ŵ������葭��RX1��Y�wg��M��dbǱ��U�<_��w��v7�ƫ�p��<pV�K�M%	Ps�#ۤK�~`�ۧd̈́(������/d�m�tt�8I`�I{�E�fS�t�3bR\>#�9"�lFd�)_����������T�MDzKɅ�\�+VR��7YeKӢ���J�����������䵹q%���Ocj�/���<M׹l���!L��J�ܗ��ʥA�y�����B�y&�ypLa�8�*���� G���hɯS��Usg���t�_��ԍ�ڻ,��E��՟��%����x>^?YA%����E����zn��������r���3;�l��v��\�]!E�U�����g�j]ҵI�8��&H��(����}L�:|}z��t�{�#���?r���t<�o��N�7���N���5h��P��$���o�(�h��'^l�d���o7�	9�f�=�e۽6����_mt�r���3�W��7�?o��^�՛w�A�G6E�@�L.]4T"5�D� Op(0��
�1%��&AC��8�X?֡�rq?�Q:�|��GǇ/�����/��O8){��������������\�.�2�!��u���<ylB"u/E�;4ń;�{�N�! .�Y�ݠ����E��d< f���(��Y[}����P}!���<��~q�%�gHwwxtx���pgxr��xg���������'��=\%ݽH������[�'V�K�z_�Z�{�¤{ۘ�坻e�F��*=�����Mk�x4�բ���^�}��<�{58�B�4�Q䏦�?.�c7�	Wߞ�0�?Lm/&v��Ի��s@��@�P�- �+\�Ⱦ�En��h��I2�;$	G!B�7t��C .�2��u 	āKq�ǥ�l�=Dץk!]��P�ܵAvcu_��P�v��:�<�xt�/���	FgF�ͬ���k�%(�*��.��CA���6t1�-�{�$��~�����;�	 z���'6� ��ѕ8�kO���)8?u/� ,w\��0$G|�Nq]��������l�G��v�tĆ̱pF:Ƹ�C&md{�0�߻I�`\x���z�;�r�X���������:�} =Mܨ+(1mnw4�H���bJ`b3j"�((N}����u���-rn���N�#LW��-�ߣa6�a��/��;����Ȏ0���`T�tdb'��,N���������:*0�
0��zw���;����/�G�GD��A!��˭������"�	Yn�X��[�'�i�����GiI��]�~��(ػl`������KD��^n��X�;�n9a�M�w�K�r���;!+��i_Ri�5�;v�O��������m���(���6<���7{��@���"��ڥ�ZO�X�;}��x�h�����ӽ�W'Ywp�S�[����V�nS�I��p��?_Њ/w����UP\ya���dz�sx����ƘQ/pq���̰����`wx(�2�+uH7&�O��*�v��4�3��h���fb[�iuXM��R.l�̳�Ȧ{����r.�����_m���� |�>��'�N���D���4�/��=yd �\B<������-�t�w�T4l-{_��g�Y�����%��!8+��iJ-�T8��'C��tr��q�@�|/���M`L <�G�Q��3��d��럐ʞM�9O���|�[�����W��f�VX�x��E6DIfƇ��PD_c�{�c����a#�/�F���ldB�j\��
��}a��.r�!�r@k$N��bo� �j\���E�ħ>�h���L��˔
Z�p�e�~"Vl���6��v�1&�)�rC����.���a��|"�KW��툰{�Y����{�/D���@��cWh0P7���!������>5/���XxC�o��Vdگy^g��ox=y;�Z�Y�vd5)`�Y���4e0M���l��b�������v����,>���b6U�F��:�D�5�����%8%��WW�^ĩ���u7;�{���S�M�޽<D�@��ҖQoȋ\_:%��<���)�����%����#m9kk$�L�w�O7?��5��W�cI����ޘI8y��N蓛_Q���K�a���M%�XOV�`"%7�&�$�yJ
��x��2�O9���P]f<r�!_�S�癦&�[r�%P��{g�L��(biF���{�Pt�+�� ��5���o���J!ܻp�j�!��F��F�"V]�c�
�):]ο����杉�D b�6���@���4��j�Ѹ��N��ͯ��|����d�ʋaa�� o%��`�TCՃ<����
�'>��7Mt@$�������Z���X��7M��NB4KܘD��=����\�q�����?�əP�0n����A�����iN| ��(XM<�-� %�y��/�簦�2��\}ł	.�&X�A��p�i�W�@���O5	�������D����(U(E�1툭�ij����c�q��x��w��d#[H��-G5㻑b��1;t7V*�д�����2���Џ�n�y�
7��)(��*�d��*o��|f�.��%#���{?iQeQeQeQeQeQeQeQeQeQeQeQeQeQeQeQ�� �\ @ 