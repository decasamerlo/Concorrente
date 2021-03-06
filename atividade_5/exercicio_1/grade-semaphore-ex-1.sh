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
��h����+�O.CkmUc�#A��oع.~�D*�/"qu}�*�C�Gd��6��PՇ�t�$������ 2Q�LTP�J�w��"�rNf\P|In���Ν��B%dwf��"�\�-�<�;E)��_D�Ԛ��rJSj�r$T�"��7\�Į7����I��`jD%éD���Ƙ�^�3�7�ٮ �o��j�l��$,0ò�W}�����2�O{M��L���Z������������>��1��Y�F1�:�����>��S~�b�u"�_�)���������3�j��Ag�ߵ�6{K��^���{f�K�����>d`�f?�p�_қ��@3�j4j�t ���U�����ߘ'�{��]�$�0�%�jJBK# ������凟2�t=1�S���H�� �8�o���I�M��wA�0sgx��ƒY ��&~ݸ��Z%^��\��ۉN�ç��9�;��������j"�=�}vx�-�Z�[��넗�W����f��G�/�����m�9��?��t~z��W�G{?�;����;�^��z�z�_D\�v����b����x�i��������������;��l��j�����n��_/�h{vO@��ܘ��y><D9Tq�Щ�,�k�g^yQ�%e��9JC��*�09�nht���[��1�4t^��y6� �D�"*h���z���6Ltx�><����m���g�+ Z�I�Ɏ�sĕE�m�#[ZI�d7ֈ3�&&9�I�}L��v��)u�@?v����\(3r�"j7g0��F��4�I����;'<ot��{������R�*�����;�g^O�Mr���|3
z�iN�F�ԡ��z7�'��E�JB�zo&��b:+b�ۜr T=|�h�ݣ�c��H^[���CQ��z�	���v�3�D���VֲT�<INVCB��R�;�J�j�N~�0:�w�6VD���TCP��ɘbFJ�q��
�j�e�`�j.8�E=��9p��YT#����X���9�Ó��fk�Q%�� ��vQQ��y�y��bN�����(�������)�o�UUf,wp�]�x��(`vN���48���
&W�죂���ַ����GlKXOt��U���+jEBŖT�~���mj?�^F0�'Oq"
�0|(�xյ���geƢRNpE��V$�HC���<�f�rd��F
�x��z��/Y��"���|8:���m��s:�D�KV%$�TEl2��ak��HQ�d��5+s�{��cO���X�'Ė������)���7�IfM�C;����b�[/�#gr"|��d�[:��C��G]�T��������yO����F�7�+Do���h^,���txz[�����B�Od5��g��Fop5N6�v��3q��m%�W�;�Aĵ��p;��d�u���fH��w@1ɑ��������?����z������K|��$;��4
;@|�s��ſ�X&&��S�S)^�c��䄡w�ǝ��9)ռ�����GB��mi׌ֈZkeM�%��H�z� E_��ɒ�	w��ɔ����3<G�z�?Y�������)fS�E6��8"��eJxQ<�0q���,�1�Oɸ�LB|��J��;�t���18����R%��3\H�h%i���FV�YJ<� M-W��SC�� �zM�ʉ"b����e�Nf	1�G:�>�z�aV��˹�C<��K�)�J�k`sk�΢w�\D%�@� �͊�,�	�n<&��!R+X����5F�<Tq$r�*ٵb�g���C��`�Ƚ�\Q�9�5�����K�D;WH'QI.|��\LW��ϏG���,)�$��B�R��(kt<�}����Ů�pĦ�cQ�94��C�K�H��W*�p�,��f��D���0Y���	��
(�0:�7�06���]xM�J��ʆ1/�1��"��!��!�HG���WR���eV��\����eS���22�)�8Wg_ϐ�&T���Y|��H�i$��ƚI�	2Խ���E��'
}�	_��<��$�\k�,�k��%�`s��Ġе��L�l�rneS��V�w6�����-�5�����lTf*�N�]8_�D�"Wz���aj�w茻�{���<?�v�œ�se��m��Q���U�
�L���>�V��(���H��߈@��8I;�Oz6j��0�f�]y��(1��B��
	>]?: ��{���_��)����ǟ��b��)���������������}wG�"������(�����l���Q�Hװ;�'?]��7��W�qLS��ҧbĚ\K)!�iV�]-<��6�x5�޺��Y=�{y�����h����.�$�]�U��J��� a)������\�UMH�Ra�2 �'D�oDn��8R�D�[�{
�kIA���@�r�ATM����>��x���� ���f︷�Gf��X������Y������?� �#}.�ʮu��H9��^GN���d�u�4b�ڕ���'��a��Ljm
�uӟp��o��ՖS�咹�\ ��X��)�xi�}h��G�w����-h�S�`n2����\k���q��W̖�v�_��mW�)P
���#��]��@&�����/b�N���h2�[��&�O��A,�\�g
���%i���kQ��D_��Q#�)h��Ng'`�=6���U2��FP_&s#��p�.�~�X���Tc�v����%NO����M�z�a ���QWɄB�ˑSE8�0ٜV��#�AD�T��
I�/s�����#��R1$q4��d� �f�A�X�Ah���'��M.�O�Ԗ�̂3<��RE�hD�4��^�b���J�z̴��2�fy�0[1f��fΖYD��2L�"�`F[���!&n�2iБ�v�9�QyQ�0^�Um�Ēa6�d�Q��N�Ƭ�~/�'�ӄ�a��O��ńcH{S3Გ!n8 n�2ˋV�:�K�ST��v�D���mg���@H��,b(�J�L�}/:��P�]b����f�e=揌�-���sf�A�V3�0I\v���~����kU~��,�Y�L�`��Y\�X�g��)w��!�|��L�@����(�e��4��7�=GSFF�'n���qx[��T�M��(��1������{r��;�̂���k������;K�����V,1O��9}�%�������oa����%���PTa6���
�&Ю����*�y�I�V(r3���m�%!�4o����_��D�ze���؉���%vV��v��J2�hKne�.J�?��%_\N�5Y���8�<xyq����-8��I�<���	67L�a��a~P�=tԝ�S4�O�G�.>��uU'���-�S�3�s�nK�[T���zb!e���q3:/%�w�_
r?ZJ�X��*\�\����Y|���3Y5eu)���Im4�19��Js3V�y����K�y(y��{�t��d֫�I�")E�����%�я��H���j������}����d����Ӷ���z������℥� ,�d-w�eF���*�ؠ��k�/ԗ;��)�Q�.�-���f�K��`����Vf	�ʩҽ��KwshN�Gw��MsY���ɋe��hU�:�x��Y��R�K�\ĺ<�S�X���p�s�0}��0j�: y��˗@��*����ӡ��@�W���D��T�2�*˾���@la���JkZlEVk�k1�z��N��qF��4���@&u�V;ټ�N��x"%5)��^[pc�=~�x/Ӹ�ǹ�{=�z��#>h���q"m���\�E<z�ۏ�+�Ls����i�-�;�Z�>�v�K�k��K���U���J�܍�A��r_��%{�5k��ǽ(���Jj+s�ܥ�9�����5G�bs� ��R�/�=O~˜�[@�[���S�9QeU#��z�ҫw�u���;��-��UwcOC�}KC��5]T�����Η�˯dqZ�I��q�魹e� ~J��0S��T-v�.K	��U\�868����c"���Pd�b�p�Sƅ�pK"P���M��$�B5�Ŕ�~�F����<Jo/����	q�/ z�Rm�6�H�D�;2�
�
ݓ�Θ�l*%/nK�L50Mj��T���06����6���(y��O��=
��Ӝ��:�Z �y��Td2�IZ0��2'��?�S����Erg��'#q�א���7�S�6=�ݠ���^�wnV洧���-j��:�wьvU�YhT�qF#0a�p�Q X�͠����Ui��7F:R�#o��9p�/��*�����EdM�Q����X�uY�@3�P0�q���Ll�24M��L]����%}�����h��e�p&qz��Ӈ�G�J=*`**|F]Y���)+m�6_YeS�/^m���h8m��.?�f���q'
�]P(mN����;��i2xA����_~����_�TU�_Y������L�cj]���O�)�ԓ�^B�ŒA����3�(�H�Qrȯ�pB��Y�w诪��(ӛ������22S��"����Ej�'�#3��TXZ>�B(e���خdR�.�<��\�w�\0%%S������T��E�i	����DM�c����S�@j���=��9xyw7��e�]�3�9�KJk���D63�OY�L |B���QiL���p���ދE���\"�����* >4�o�pZ�A�"o�JJ�;�	4��B<��Fހ6Y�X� Zٱb���-�b�Mv3d�T.+����F[���B��5N�R�?��+��%˕�6R�����	�o����?�/�z�r�:��l
틤�S������
$d�ɉs�s��bM�"�ؕ]��&>N���x�=\Χ�&��N�wW��mX�����rܵd���2m���N���o�Ý�����']�p�X(�q�;�v�&���o;Q�a�����ܛ�q����r ��Coĸ����fZS}�^S���o��#wU����s����9mG���q;g>���ư�$|�ǟz��`�e	m.&��Vnt��f���q��L��Y��S�+��}�㸰�H;>Y�qV,Jl�嵢-�[(�ׂۜ��jo�C�-r۷�X�� *�H,}�_�2��"��������ˤ��U�48e9U�<ãO�x����\�J������d�=X@in�$�{L���\S>߆�����r�w��O_��������Qt�������Ͼx����&����}��{Ϸ�o �j�W��Ӝk����'��7��<����^�(�Sf&�Z��8�u����I�ʙ�/7dk�
35�A�J#��M&�aP o���w��.� ��~$�p���-������LF��^��l6���ݼ���X���e��.��ˈ��=��WsUnIe��
&C�t�\T9�� ���:�������b=�Ҭ<g�e�-ʗ��Y�ɬ+c�1<ߥ���ɔ��17 ��8��������7Rr��ř;<��U���'7ߣV�Y�r�5�6�����:C��bb8X��5�J�,A�dh��3����"�3�')������c��Ю^�W3#a��e��I{��-��ߠ)a֎�b���c�(��u۬v�Jۢ���LΞ4���^�џ���_5����i#�&���-|�� ��7W�u��f����?��eο�-������p��J֨��ݘG��&#k?��P�`:r�C��M�{�Z��TXnW�x����t�D*�u=7�D����襡�b����α�s�!�+�Ǘ�����?E���2�O,�a�=_o�v�Uy�w�#�n&ސ���#���d���ODR��}ޓ���	��;�2���۴��`�EٕL�\�4%��j���{r/Q��ڃh��6
�?,������_,���(I�c2�6
���(���������������g�S������J`�т��B���g����������8�b,g��Z� ��eU�ۭV*ʝtP����t��uͷC�Y���P
������	��M�ě�f���S1��jr��1E2���a�Nyt�,vM$X�K�f�#5,��b� �gW�A�A�n�q)�6����_Wmx��&�H�����?Hp?���M�;#����Y&���>Izk��¼,A��i2}:s�ZU�7Bh�����À��'����^���t��d��Z�A������>�'7�wz��&��]#޷���Hٕ���3��[	���N8�c'���P/`7S�A�	N\k3-c��P��=3�F����5E����Bʠ*��5�(ʐb7�82��޸��qq��&-�ǐ�i>��Y�?]A�)�|LgE�@yؿ�O��z��&��s�I0�!�A���O5h8ڧ����VG���sF�qz(�y�, �wI)�y���e).)��kG���H
y_<z�e���}���=\�7Rn�tN�Q�ԉ.*���/��T4�rU�#��{��C����Ȋ]P�17h�W���:xyr��dSDS#�Ǭ�z��h:෕�l;zW�th��K�*�����9�l��l�>���9̖�?t*�1{͞�0�7��nCտ9>ΡU|�a�Q���+���8_V@����$��j�u%A�.^���ΤĆ���>�+���)ۨU�#��Z���t< 2.��v�%�t��`:����H�=d`Ȱ��ý����,gO���*�ak����/�OL�!�Zn��~�ͼi�g���5q*T>��.��J"� zQ>�Z���>���k��������8�2ο5P��YK�
@�潃��Z�8�$����a�p:��s��;�C��޲�j��iD.�[?��b�������M�lru:ۀ�T*�6��n�,<7uOg�<d�*9
Z��I`�������e'�������n�We��_���IÉ{��l]'9�3�����O�Y)>��B���ۙ�q����{#�%�{c7<\Q�qݿoY���՗5%E�����`�`BJ�Ee�����7��x�쎛�t�W�E�=�>D�$�c23!�eX`�q����o��4��U/I�k�l��h�6��"Z.��12
5��U��P^��Vt�Y2��O��.����/��ŷ�?���}� ��՗����'�[O�7�*<k������m��^m�n���_k���Z�u��Z{mp:F�Ϭ�Z;8�7��㷯�ދ�z����X�,r0��[o�q�o�VMG��
�&W�u<*��X���^�����d����&z,��|��#ܿ�gސ��!hq�ٟ��1'�y����k�A׃zw��) Ĭp�f���4�Z��~��!�1N]��&�F��o����Ш�$��9�\2e�n#����N���q�E�>��&�6.�^�6}�ؽ�7�3�O�C��~��f-��0� T�=�j�� ��p�Q��:Խ�L���ӆ��}@ �Gޤ3vp��3g��ܖ��%87�i�{#P���w�KE�=?A�����������N���Ym�O\�e}g�����p�kF�-���?y`�q)<�\��@}'t����+�v�vv���@X�P
�Y<�d�P67�Hd�I�"b0s87QJ4�C�J�ǉ8lc��9oi%�w'I���ʡ�"�'\�S���G[M���O�(�Ћ�W��&@�ؙD��h�� ּ�;� ��글��0�i��#�*s�&�u��կ(G�GH�?p����"��l�
�b�1[�A_���9%�q�@C-l��ڒ�F>O?�o�m_T0	ʳ����3D��^�mo�Yk��Q+�ފ.�!��=;�1��n(�����F#���C#���E�����C�����W�xT�	�7>��D���*�X�w1���_�S	Z�9�:�=y�b�d���qBNߙ0(U�P�76+紣C$���|J��a=��!.A��c����>w���]��;���#��zF������N�@�e�W��V�<��«U�q����r������6W�J�z��ݭp�O}'�&��$=Bʅ��;��u�jC�%g�k�9��-�u�@���| �|A;'�Ԟxp!�޳un�f�A�E�asկ�)�v2��)����ڊ������UErj����}r��N�����QD��b�O�(����)��������'����D��1@�Dӟ���J������o`3j+�������&������}3�8�6_�����"lD �%��y�m�N�EM(��IJf�;|�=x��|p�2��a��jAT�8���o� �t
��@�J��uJ��&n>��'r�h8i�/9m�q����W��<���v���x� �� јx4+�o]v>��s�I8�W�F��7�?� ��<i}@G]�k�	�A� �"7�M����PL���לݛ�T��c�N����z���\�Q�ڭW	0�,�z˪*�*���ɧ[Ͽ��::�j�0[���� �ϊ�����~%��u>���ʭc޼'�6�j�݋(��e�nl��O���[����r 	�M��"P'���B����{ZSb�e��䆩c�n���Y�p� �nцO+݁��ΐbŶK��h�I0}�����P���K�0���5�V/H���&�8�DJ�>�9�x� ��r�rQ��.�H�/�����BS�5%�����D��T���r�L�pƌl��JES��M2��c����b�a��F�pf#Z�+el_�0�F���G�.4��S"F�!M�� C"�i>U��l�r�+�N�����|����lk�G0�����Ġj��<-���YF�I�O"�}#�I'�M�1nj���P����U>��tK��1���w���7�p�*����p�SD�aT�	h� A���5���4WC`��8XM<�-U'`%�yë_'~�7-���9�3p97�$���7i��7�1H�G~lI��xԺ��f�'�Q2�#�1����i�m���s۸}x���w��x#�X��/G����ys{���ċ�J5t�����=4���яh��,�Є;�9���&�◪&ol�|�D����n��^OZ�eY�eY�eY�eY�eY�eY�eY�eY�eY�eY�eY�eY��[�4
� @ 