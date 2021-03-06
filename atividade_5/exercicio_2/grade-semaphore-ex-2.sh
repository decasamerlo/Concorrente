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
��h����+�O.CkmUc�#A��oع.~�D*�/"qu}�*�C�Gd��6��PՇ�t�$������ 2Q�LTP�J�w��"�rNf\P|In���Ν��B%dwf��"�\�-�<�;E)��_D�Ԛ��rJSj�r$T�"��7\�Į7����I��`jD%éD���Ƙ�^�3�7�ٮ �o��j�l��$,0ò�W}�����2�O{M��L���Z������������>��1��Y�F1�:�����>��S~�b�u"�_�)���������3�j��Ag�ߵ�6{K��^���{f�K�����>d`�f?�p�_қ��@3�j4j�t ���U�����ߘ'�{��]�$�0�%�jJBK# ������凟2�t=1�S���H�� �8�o���I�M��wA�0sgx��ƒY ��&~ݸ��Z%^��\��ۉN�ç��9�;��������j"�=�}vx�-�Z�[��넗�W����f��G�/�����m�9��?��t~z��W�G{?�;����;�^��z�z�_D\�v����b����x�i��������������;��l��j�����n��_/�h{vO@��ܘ��y><D9Tq�Щ�,�k�g^yQ�%e��9JC��*�09�nht���[��1�4t^��y6� �D�"*h���z���6Ltx�><�������#��֯h�G$Y�qr'�ýذ�7�M�A`b�vF±~L>��=g?��_��U���B_���h�����������;�׸����FG��;t�6:�@�K(�`ׂ��,��rm�k�zN�Ѹ����8A
ڭ�g��eu��NdG��7Rr>��1�m�8j>��~����6?��oj�����Z(f�B0�%�E@�
B������`��R�"I(��Ր`����߈�lcx-B�?&�ݽ{"�Rt��)h@�x�q'��q�Z��%5G�j0�4��b��.��8H�,��N�@e�|m��v�$�<G�UW�d��bR�o""y>1o�_�鿢���O��?��{��F߁7�bU��?8퍮w<�w0;'@�vB��� �Y���}�QA�
�l����-�%�'���*����+J%BĖ���z�:J�q؛�	���-.D�<�/� �ֽ1�b��&�������I���P�G��1K�R�82��7���x��zk�_�<�D<��pt*FQKچ��d� ��BرR�ɬ���e."Ee���KV���x�eO��X�'(M�&�..�@2��Mw�Y1��Ψ�:^F{�x�L.��^�|Cg�vaj�}�p�,{����g�}֕m��y#�9��ɛa-+��yJK<�̓��0�dY��D'������7�N��s�H핪'+$cUZ(w��&ۮ�Ť�K&ܐR�:��t�#���{�ݽͿ��'������f�bn�30H$���vfI܁�w8�:Y�+��V���J�ʞ+�� ��3�=�'�̻�V͋����x$�/ܖ�q�����%�V��]v�ei^�?@�7��d�����r�R� ���'����CI��SU�h�G�q��)E"yD@_gFx�Z}��M�vK+3#��/�/?�i�_�_i�b� �&~]�C���(E2�<E��n,�݀ی�³�xA�R�jw��T�5�U�)����"�|T��LwC��p��곰Kf�� k��=ģ�s��^y|f�;X��䋤d%�<�s�B#�E��s]͉"j��
^3��:�y�^q$r�Urh��ς{3OO����e՜Xs����h�2�4)I��x43������C`P�+R%��B��Ғ1|t<�}�����)�Tb�Ա(O�94�dC�K�H�N-�B����@�N���,ۧ�;�t��h|����"V��o��{\�c޾*Y���i�p#%�Z�XIwh{�Y�����iq+��+��f��^�+����cf����K�������Ϥ�D7̽����֋�-kOz�dyzqI��hY�VK6���j7ƉA�k)�h�V��®��-<�j�,-�s�{�k��%׺ި�"�;��D�"=��3x�r���zaAĞ
�ݙg���>�rߴ\Y��۬h�-� F�l��&3 ��;Ϩ1ʨc5�� ��7���������덷/���Sa]-�"F�3�����	>]>: ��}���_��)]������Ì�j�R���jg���;GǇ�����w�S�X	tEr0F �;u�u�?!�]��83�5�>��W?����cLSd�ҧĈ5��2B�Ӥ�#>֭�xt8{7l�ʛ�o]�ۤ��8��boG�MC�i��h�.q�[u%�rX��)?$�`X������Ou��ˀh���Qw�\�y�r9r�g!�g@��q�$���$|�;��iP��jO79��qsA-��j��u�wi�l�%�y�Vcb�7�|���\�����q���ص�<)`����	ݟ�,���JC�Ҵu���S�МI���z�
W������l9\��� �Ŧ�O��JK�C���?$��n�?ق��0��&�Fy̵o�7jx�m�pg�����_w������x"0z �Ȩ��A4��(�xt�|2K�#�%�m��xs��O�|�p�6YtK��QKTM��Y	�v�+���Ng{�^�l��dL���&>�k#L��p�.G�X���T��v�nt<�
�FO����M�z��p� =�]%
q/G�d�4�dsV1��p��Щ�;ZI�/s�����Y`�͂1<�2�yd��e��J��j����TGui��,(�X.MD�FdHs�w���W��qa�G��5����l�Y�1+��ZfE���Q��T�!(m5J22�1q��I��T��q���?�: ����)��X2���]�8ʢT�	WE*Q����4b�0>��g� �c�1�{SvVᲒ�n8�n�2ˊ6�:�ˈS4��6�D���me��ɀIP�,"(y��&p����(�.���� ����G�ҖGl�9�Ņ�M��S�$.{�#�����t��o?���B:���*?i2���L�"��:D݂J�d���,P�C_��@ˍc�;r�dd��pz�o2�W��w�\Aݔ����'�39�Y�'g��a>h��'�}�y��PetV8��TA��~�a�GѴ�I�3�������O��-,��Y[r�Ej�m��/a��H�my��kL��P�f�+��m�%!�4o����?�W�ѽ�^씓ы�����ֳ����*ɰ�=����(�j~p��|-p9��d-sC�q�y����=D�*�[p��I�<���	6wT�a���V�+eg�����/)pݔ	`/�F�T�L�\E����[���#��X�RV:+�7��R,� �� ����`��y�˟�d�8���y*�%�.Ŗ�"(i���'%�[ij*�go:Լ����g��3U'�iAj�y��1.�S��M=�]�=�֐5LMը÷���zu{;��i���Ӷ��v;ɓ�}�8�SzB�>�yf���MHJ���k�wN9�˝^���D��Gmlc)��b<R�/+'��U¹r���e�҃�>�ᱍ)~�\��|�bIg9�
Hg��>锼,E�T��H��v��n2�x��c�aF�X'B$�q�^��	��U��C4��b6�G ^���_^"��T􅱄n��y ��]o��5+�"�5y޵��v��N��1F֋�`�2��ˬ{�d��;�k�.D�kR�������6Z��pN�L微r�w���j�G|Pku��U"k����Ģ��eO��ۍ}����|��e�G↭4�o�����rYm�4�H��������X�T�/���Z�7]��[y܋qo���27`�]
��|��M]s�:��t A�J9�xj�<�-sbdnMoQ�~�3O��D�U�X�klk؉�J{�%1�O�,
�;��-�B����ar���apزͪ�F����y8���+I�fa�*yl\xzkn&��'���=S�=x�RL��D��c��Z�=�A b
�5�)�?e\m �$2c���i8��gP,�c��(f�����)X��^:��� �]t_ �q��t0m��Z�;2�2�ݓ��YT6���隂������Iey1?
eS��x�;X3�_��7�����ܳP�h����O����Ṿć�&i�,\ʜȞ���i!p���	Z\��J�3�������t�ޫh�G�޹Y�S�vSh�֨���1D5�o���B�ڎ3�
�+h ���z �@��7��̿��W�{o����c���Q�7�*
\��⥊?<4qlY�$�;�b��b���)���d� b��!i
�dj�J�F�3���'��l��e�p&qz�����G��<*�
*|F[X���	+k�6_XeS�/^mj��%��l}�O�9��q܉�fJ��EdGk�>`|�'/H�~�3��#5E��<U�Wޱ�,�|�|�z:��e'EX�0��p7POz���A����s�d$�(9	d����m����y?ʌ�C��!�����%�H��p��̞d^c䆶�
KˇS��8�Q��+����9��6�]3LIδ�g�3��,�JP�(>-�aYt]��pl�җq�Hm����g;��/��p�?�ӡ�sF<gqIn�$��e33���J��G;�Ѝrc��7���O7w�/�	��b��L%Y� �ᰠ�gx��r�:p�����H`A�u�9��K_���(�&u�=�Vv�x>k˱�w�b�"��eś�"��X�>>.�Ԛ���pTJ-^25=�g%ˍ�vR�����	�o����`�1._�c��C���W���5 ~��@B����8G8��(��K�]Y���W[�89���p9���x4�e���'n�Ze������ �\Če�%v2��ώ��61?�	�hM#�E��*Bl2��d;SJP·��I�a��=�c*�p�&��,r�������̴'�e��3@�|<�!�]�ҏ����]U�8ux��:;g툠v�1o���]r"T�I�W~��'�
f_��b�x�r�`X�5����W�b�������_����KǅD��Ɋ��bQbs.�˙�m��ns^���������m�N���zY��2чy��(��-�����/�f_��2��ip�;ը�aѧ���Q��n�4x�g�l'���e���l�1ĶrU�|ޫ�+�]�r�w��_���?}��B�(��wyeս���O���w����=�Ȼ�6�o �J�W����k����'��7��|�I5쾺��O���jJ�0���STV�'�*g��ܐ��
\�I�E�W���Al |���~���M ��D��;�=WPē� S�3)���	.����p2���-��bu{'�C�K�<�-#�9ޣ>��WsQ�IeawT�f����reI�vq����A��=��iV�����Kȣ��d֕��������y����� \��������o����'�J^\��k_��L"2��;J���/g�QR[�� <�ڢ3��Χ�A���}H߼�W�W	�%Cr�^A�ג,��N�$�O�v[O�úz>]8	�<U2&�n[����*�N�b����(����mV{ _�n�d��"g/��BG����Ows�/P������uS���3G�R��^c�xu��5��o��mxmF��&���Y?���d����U�8�;r	!H������g��q_��
�k����r������ap�3@M�E�n�&�(�c!�B�^�z
gvx�w�娸�j����?�l��|�����e�?%�xr�
}����^y޷�#�^nhk�SƠ���g
�u磧	B�z������y������x�6��XXQ~!��띤8�eC���s��^�K<Z�CgX{�L�F������}��ɧ���M<z�1�n�`�m�����������ă��G�S�ϯ����0Nd������]��ѧ�o��M<���`�@&��q���c�*�zx��X���iP\�U@u�Z��;���A<��z�u��LE.�� H�]��fÐޫ�©��؝8ptdy) ���Sz��j�b�Ca.��Y���S��j����d�x�UN�՝[VZ�
���zD��XiwD|;���h����'d�r������4:�#0 &�l0>		;	���i��؝2c9H
���ŷ�/���d�(*����豩dAx�R�O�.����oA��E��P(�x
%d_�߆g$�8�{V�b�5������]%F���U�K,4lMt[2�6#�ZΞ�Ӣ���s���ӓ��D�uIV+X����w�N����=9�R7��a�q�s����Ú��P_l�*�t!49�6Fa���Uog#c�����H�����V3F��1y�]�����tk�[$��S춾� ���j��������CF��k"�x�1\!��A�'�Q1@�\�S%4���e����P�mHp�L�E���y��A��/�Xm�T�'�|�V�avz%g9EUɼ���:�V�[�
4]ye��;P���%�Lqa�����7ne�]\��0��}Y{�8u[l�'!U>L+h��tV����2�N������ԧ�	@R�����x6���XD�|�]z�%j-�oT��x�|S�E��'���&���?���Xr�aZ,hƝ�v�s����?
cN�UU�U[`�F������8�ڈVS[#�cuM{*�%�%&#���_6Y����
E�_�_�����c���8s�OI��M��(��r�c�u�r���T�z�����gC~�(�pS����L� dN@NLA�?����D�v�J{l�����)��&�òı��&�(���5th��q�*��_�
ÿ��bMw�`v	I��ThHWS���Z��{�
�)I_�X��R� �-և8LX���*o�ŧ��1��Hy����
xq�'����`�
�'h� )f���ŀ�ǳ����/�!�O�)ig���#���$*&����B��d���0���d4��J���"���~ʷ-��3Yo�n��1�4#~�s)
�Iw�#0&Ol���,$��v�C)5w�t�O�f���H)�Z_I�q��.BS�V�h	����/�?�q��?0��j�={$p"��G��"�XՂ�cU�5�3>҂���h6IW�k\��u��{R�߰�,&�[?(�>}�8k�gee5���x�v��F��K��h�5�"o[da�|ܒ���]5������Ħ!�,�L(Ƒ�A�*�qk�
ye�k�������-XOX�^tF�� �V�0��g@�^�\�f��$���5�߲Q�4��J��z�?�aP�M�3h�W�F���m(�� b� ���>�c�I���O��I4>�����j�=�l]v����=�@v�D��0�^I�ݘ��Zu��	�\9�x?V���|��j"J�\���rp���p�Ywo�醮"H���*���r���qoI�S���n�=�۫��2�/=���B;B�b,L@��gj@3��U�����g�G��y8�!^Ԟ����?~��J*�������Go��a]j�/㌏����O읇��m>k�Rj���}��v��q�w�?y6�x��Rv�e�?T:���͆`+���~L	on\K'�_u��y�5S��l4���
b�Z]C�%lB�)Jo$0y�&}�D7��hF�fW���_0[q�@	f�U�-a�N��4��R���m�A�0�`�=��%`ë����à���qE�=�fXw���\4���y�}��>X�`0��ЛJ�6��/�T��ݚ��!+��˒���lA}����汧���'���9e����k_��f�ũ�T��~�\��%7�s.O�f��
�_��M��u�Z��W��<֖���pʬ����`m�1�%���fdn��J&����j��*ch�L��pK�V�~���ݨ����m��s�`OcR��B���ꃙ�$*sY��+'�b��Ϳ�����z�r4Ҏ�(�SS�pIҭ�&����σ24S��g�<��la�K�R>�?}�ͫk�B�틯/���e�uȐ�9��"��|��'�%�o� �s�Ӵ�o���7�l}����hCH��v�`�h���V�h���������-�i���Xk��vە�t��������ͯ1������^���at	k�&&tn��u!1_��U]a�Bg�+{6�[X���>��������tK�$���ςD���0����0��� JX�c]���~3�6�X� �-p�f{��$[�R�^$�3��l8���R���a#j(4
ko ��ttY��JN�=�mA�P�������F��e�����o$(;c<��WKPS�%D?���J���RP(�t99��P�|:��u:�O�Vҋ M ����$��Nп��~+ ���޴��Q��k��@�޳c�붞=ۆ����d'�h���k���|�z�(���	�a͡,��H�B0�9mܫ�@� �F�W�|����s�?���
�S�=Z�q��no: �(ǰ|&D`pj�δ��l��B�1���}���N������I�����`�����ж������&�QqL�Ȏ0����Ymנ#�`��N�)�X�6�ǀ��+��ld�	��0��>��(��c�fW?#1%Ϩ�ʽZrl�
�b�	�W����=��'�AO-l��Ғ)��~B�W0	�W݃��i�^mk��Z;Э�8i���<9�%�����G�����촟��B�Q�����/�N�#�u�݀Wu�!��Ktۍϵ#
h���?��#�#�ׯ7�_�x�u����Hw�L�<(W����6*gVSD��4�~>��_mb9��nA��s��.�y���p�Z�� o��=��4r0Îw��w���.��J��+��V�� ~�*w�\}��PAns�m��7yI��F΂�I�q@�R���r!�����P|Z�'a���W��c�Κ�j"�C!����1Gp��KY%푭�t5[_�-���X����,�CAX����H�J�9��HJݫ�pv�<�t���_�A�Q��&��z��S>�!
�!Ìǔ����'�r�B��QA�$�ෘ��J����[�f�Vx�x��5D6DI)?l0���hg�6������"lD@��_�:��@&(V�Fn^���g_��^b*g܍J�Q\���RE5.�B���śDgC� s�&U��/3��p�e���������u��gB�lH�y��?[�peA�#&���iH����gg3��|=Ǖ��{�oD��#�{?��u��!6$���x����.m/V��`�E��5'��G&�?b����o�<y�߸��u�^%�(�X�-��`�짟��p���/v77[8͖��s��"h(f��Ы�%���3��_��c7���_-�{�(_�vk̖@�ak��}W�s'Q~-�0_���-�s��Q�t��s��ՔX���I����a��7z++L	\� ��[���J��+w��cC��S6��x����8���~AA�.��l�WI�X�T�`"M�~�F�q"RR�`��[D���sd��2Cu�y�\#_����LS�59����-���X��r�,���9%ؽ�+K�b����;g�^1�0ge#@��Q_�+yl��0KG���{*&4ߛ�K"F�!-�_AZi4�*�j�V��9I'���`H>�xe�%ۼ�XX@c�G�{>�z�>Ks/;�"��4�7	���G��`\��`��J�a�j����*o��,�a`
���Ĵ����΃�J��^4��$�f�Th�>�C�X���p�Q��!�l�f �G˘�����ӨǛ�P�]p�&�\�`��,��Y-��0��g��$˺���5��jq(�QR�"S�1����i�m�a?�q��pgkw��њ^X��-G��[߲�v��:I�X�jh��x]�{�RӮ��O��p:NP���)hz�
iإ�ʫ^Ԑ1n���D3��'�>���s��>��������,� @ 