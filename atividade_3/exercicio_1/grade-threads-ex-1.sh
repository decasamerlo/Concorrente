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
�      �<�v۶����@'!e�և?�J��J�S����M��.-A7ɒT���������>B_lg 	~IN�ww��c���`0��c�W�Nֿ�lW���M���7[�]]ߴ���nwk���~�jw��߰���Rzͣ�	�ƙ�wnT�����+N�?��i�Y����������:As<����{w��e���������F�ֺ��_�������+�[�r�I����ˣ������[iמ��z����؝r�zl��]6�k��cv�V�5����.wY<���o�昭�T30����g�3$�������7�g(�wn���0v��E�����:132�Kr�WF��J�k�`�DE#����O#N�B��J/����k��_�I8�aDW��vgc�8������/q�w��t>���(����iM/
]�:_6��Wٲ�_�wXTs�����?`L���l�6����	� d���O�l��8�@� ��P�򆀪3�b����q/�nB7��udQc�qi渞�?��z�To-���r&�d�z��
�
��xl�"��K�2q�"t޺��V��y豶(�Pu <Y��D9���?��w����� r���F���9V�����R�6)�R�L�o0ET���Y�c�a�,r��Xu�e@�@��`��Y`9�ga�i�*Һ�h�6Z-��-� ��EgW��
Юe����xa�5t�Sh��zS�Đ�V�3�k��J���Z�	t�*�.h[i�.�``��{3iI���3�RM��"U���绥ߵ��Ou'�d*I��)�v�� ����.��R���|��HE#�r��& ��/�1����N�濷�O��e]��]\�ůU� ҋ����/���E2�4+��U֫�r"&[���Zs�u�pfY� ��c�����Ayg���z�+�ľ,�_����>u�W�i=�*'��r�cX�����m���t��Ȳ����K�!�c�T�Ap�ޭ�K>��P@�F|�z.�&Pw��VR�
�Rm{(*o�^�b߲VU�su�����H�&���65E�[��ʃzj�H�XMʳ!eM�LR�s����x��W�Z�/yh��I�C/�@K�	G'���%�b:l�w��v0���qq�
6E XTv~�dLB�5�i����y�?>������G��}PyM���_���C$�,����������c@�	Ӂ$Vۙ �@L"�xOUQr᥹�`^D�5S�,�-}L�R%i.�G�v�@��ъ����N ��P�q������?� E���P��u<A
1�N W����Z1�a��D9b�J��Q���|n���в��n%5�������^r<��O!+�M����a�Z+�u�6��f�\��������
!%�r��j^v���t����S�L�R�GܓXS˕1���tM�.�I��Uݐc����a7NDR��5`��i�_�k6D+�4��Ͼ�y�Ih>��E���͜x8�z(S+Uڜ�����"�(8�ݙ�b����&��Y"R�]��������:������_�n�G��}.�㚣j�H�*A��:A�)u�Q��j��s@�J�څ�u@�:J?�!�����G�ת���;�YG�����vW{RJ�v��l�V�0�D>�"g	(bA;�P+�/���G�.���3�8*��Ƃ�����$V�дE6�%ۈ��+�ۮ�W�uu�]]������Ҿm#(%����++KxJĘ
M#@~�	�嚰�lKr�ȏ�f@S -U�n\�J	�.OL�R�ã��C$Qy����M�߽@������u�x��q㻫c��_�S���܄����_����^��A�h��[���O^z+]��>:9~�[٨=��~������YC�aM�+��`������ͧ�Zm�F�=�ѐ{#���[f
K
~���Uv���{�⋦�w�c�f w��m`d�V�q�O!$�|�J `qoO��	��r�K��ȴ~��b���ݲvD��U���a�u�b�4⿲�L�/M9�
u9<"�����&]�d�`�Fl��'� ���]!ϗ~��Ϸ|�bw��5�(��|�^��|�>����)���x�Fn��L'����`��A�@� sΚ����?��'�҉v���� K@�q���J�,�P�}Y��=��"����/�H��F)�)�J���n�Gl�W�GF��x����2^����ح�]�jT����^��r��ߜ��wQ�2������������/r�����t�o��P���q�S�QNy���z�Ip��n�#�r0���]��|5�1�+g�f%��R� .w�WZ�K'F�"[, D�iL^8�������y��Kp_�ͻ4s�_-���qf�1Όe�C���}��5�7X�?�g|������_i�Є:�!0��6k�v�qF[m+	 0������E0 �P��Npu�4�j۲T%E�ٹ��,c@� 2@5��e�*J��Л
�ߒ��t4�k��N8C�s:P{�����~y�k�1���IhC8\��4��;�V�S����g����7bd7�(�&hj"F����J��_'�!{���\�b#[W����D:R��ˇEK6P��6��7a#@����:��.V9م�`�3�0�j� �.I�X����39��ې����p� �1BD� �K�R��&cvS�	 U+b�>{�_��Z��׏,�=���׸C^���Lݑ�a3)[��I���`��]���l����/q�w�ވ��m�c���`oprj�g����?�?�v�>�:���@',f�q:H�����h�_ٸ�mf���6Z���>�G2�0}�C��Y�R�������K1��#~�pӹ7�Y�9�!F����R�^ԓ���|��&��,V��m��~�ؾ�����T%��9� Ȩ@d>4��D����{ fr���χ�ӹҳ��ǬS����Lʷ�{����"���;��TX�N.�����q뙞b��nn{s��5��3�]3#�:��9�`�+�o��A��@��<N\x�)���¹gӚ�߬�oˤ-�C��[�-��z��?
Q	Uk�`��Jth�Aqc�,�����c�|%�m*"�����z�ɩ�u�ws-��_$�s��U��_���ȵ�M;�����0���	��:�l��s;[6s�I�}��F&Sj�F��#"�I���	�^��L��3w��3�4�Q�zS�i#� �~|��	̺L���B`�/��ņ�|�{�5UQC���H ����c����o��W�9�>=:�ľO;�9A�����*D ��L����"1dA)�eU�#K�ڵ[)�,����J�J��R-~p�=:��L8{ec��`'��aWϝRkR�ܴ[���b63ϙ��F�l@L�X�hH���09�!���g	d)7�3"���l�4�W�	��4���RI��X@�F�0�No��$MR��P����F8R}�D��JT-�#Y��y���)���H�
y`���Ì��ʐ��]"\vQ�H
�������z��iF*2ʝ��	�eV�$�T.CJ���i��yWPO�[���-�}C��<GuQ�8e�AT�k��6ʦ���T�)1\����*�[42M�ԌZ?�'ĉ�mܙ�t�H�/g�X�@�����}�TD9�*�&����Z��A�-���Hj�D�Y|.A��K���eҰ$a�[&ӓ%�j;��,�b�QTTE�]2QO��նx�ʾG{P*ۨ��Ez��$aj0.�fX�[	@��	�x�`t`���(sT�B�%���B
��5U�e�M�A9Eo����ݻ���&a��b�Ɉ$3 t��h)�h��(�Wp�]�)Y��8W[�6
YϹNV���U�k�VP	��7N-Çr�+��d���'���@��0#7-�fu�
��A��9�/�?�#�Uȭb�k!^��AZ����[V[Ȍ��l�љ}�c�1��]�89>��70�e��`a!�E;��Y�#�b���u�#M�F�dMLM(X����%�)���T<I����)n��XڃG��Z���S�kk+�(1������2��xQm�=�7u�
�W���L�u�XW��
"�t�'��J�J┼j �R���ߴ�Z���Mޚ���SG�,�)N��C5��yz}|����s�,����3\���� 
H��bu��}�hg����3D-I�D���f�����<pï�L������9�B��x��a~�%��<CE�?J��i���	�R���w�X�JO@��'Jv�?}����2��a��!
����O�����Y�`_��ՈL��	�"�c�0������j^���Z:g >$���7j#��*�X�/L#c���!�x�N�53�ձŧ�2ӫ�W�,�����Kr���n��Z��:��n#��N���������	�:������xo��6�:O����ؐ�6�Z �=���x������tC�ݵ��[t��6Ann?��f�C��2mG���I��*������e�Kj���)�l�AgR�&����oK[��j���:=�F~�k����-5 �� ?n<��ܽ��u!��htk��
�3C �N�ҁ�_���ujf����^�8�XTUĸ�������L� ���573G�e���. V 9j��<h�뛖a��6.�����6/�c�Ap޹L%�7����m������0t<&p0��JNV{��i�N��M��f�2�E����@�:�b�	�j��,ʯd�{��Zs���.�p5G$��ɶ/�`�H�,�[��9n�01jD����N���H�ԭz�?�[�$��|̩��������Zqq��2��X��?��0 5��ٵnwx�l�7��=�%�_ݭ�n~����5���\e�_�6aU�W�V���'��Sb	�q�6۝����#����N{E�.Z�bʨr��_�o����508t�~����~��v�t�8W�󎏬2v�;���b��Ȇ	o����+4h�W�rr�3у��+I$vVPx�GC�%\����~�r05�n5�"�;DG���H���$n�TEBu�l�w��#�#��P�N��g�v5Q%*���
V��ẬU���|�Ɍ�/ȍ�VQ׹�d���A���SdB_��e���"�+�ȟD/�5S�唦�:��H�NE.��O�Ǯ7�����I�� jD%éD���Ƙ�j�3�7�ٮ گ��j�l��$,0ò�G���u�cY���}fo%�_{�S8������>�u��c��,r�����R�]WD͙���:�����{/�g�%��^8C�v������l��b�������Lzh�v���ǃ,���Q�	~IkN���Ȫ�����r`�W�{*Sk�c�$n���z%	e�"��Q�2V��Of��쨬<|�)��I�	�G�G�΁�ि�n�$y,6�>: ����p��ƊY ��&~ݴ��Z%���߂��N�ç�n9���������j!�=�}vr�-�Z�[�q��7�W����N��G(/�������m�:��?���w~z��'g�?����ɫ��~��j=n=9*".k;�@����x���"�G���翶;�y�����j���U6�9��wP9���S�5�'�FfnLZx�4_�����T�µ�s��U%e_Ap����kU�ar*���4�/�hM/�<���imI�l0�D�"*i�Rh�z���68:�f^ٱe����^����z�
��@ʏ��W���~��[n+ߤ|��Ϸ�+?�S¹$��DNk�@4��j^����JJ�dC�-�N;�>K�}����{��6nd�ͯ�h�!e^$�r��r�H��sdK+ɛd�,kD���I33�'��<mm��)u�@?v���2�%F���Ԯ#� ��F��tG��C}����&8�E/"Z�&�d��Q�H8M7�氲��H�Kr���t�����պ�`�8�!ƈ����X��SMA�!cn�ak]T��k�7,�j������u�9g��A�gq�|�tƪ���h���!�VU���O���U�QS������b�����s��o�ٝ���Ǖ�Z��f������z�a�T������,8���
���}n��3]G���UQ*������S��va����Y��Vo��D�A8���6�%ŧ�3�Nؖ$���5mYX������j;������䢖��Տb�T<�@}��,�a��B��5��V�P���;�"�C+d�=�>/+��8/Y����5
�.����JD��N��*U\2L��;��~�[1�8�``��Xb���0#Hڤ�o�w��Ԛ]�9�Ѥ�8���>��6�##]D|���@�㸑Z��+ݍÒs�������fdY��'�0&��w�b���);�z�B������N�d�M�����%�v|�ŝ�T�����vo�_�L����lS��+$>�Lt��zwG] �˹���_E,��#���T�W�XqG�xQ䟁� �hZN�z�(�H1{8�a9��O��3���D�vI�-Ҽ�p�����b*RqJ�L�ʐ���pDA�C_�'/{�N��p%Μr6eX�b�j�=�ź��������tF�a���B��$��+�WNC�,i/����|s�b�T�<��'窱�VTl=�S�0�A�Z�n���	*͆$�E�P*�&��3EF�22�g~�����A֜�<ģ�8�MUZ��k�iw}��"�H�ZpnV(��B$p<{�(��rwθ����Pő(��b׊=�S3%��"��
E� hN�!]�~�v��&qE.�����������H�x�vuJ�LF[.�����l��#�H�I�,��㠛C#H&����D�n��i'�Sd9~.�&7s�5ª4�M 6TB@%�q�|+cC�@8�7d���+��|�Қ�X*b��yD��t�hk}%U�m��PfU�N�K�3�tY���|ߊ\v��-���s�	�$��"�l�R���]Q[�֚I�	2�m�ۙ��ڭ:�(ts�bE~qE��hU�v+6pc�-}��Z�C.Z.�\X�V����F���Z���C�f9[Aq�Ԟa��vٹ��L�(r�W[gz�޴WZ����^���/w߼��g���pm-�4�g�qJ�@��4@Z���kj�z��w1Qō�[L�Qml�컨q���`z2��h���A��
	>[>: ��}��{U��%��=�bG�i��������;[����9:>��jg[�"��>���p)���b~R�y�����돓���a�O����oͮ�9��3�=� F�ŵ�}�e�|�3"�q�ٹa�LW3ݭ�Xu�u�c��G���툶��8���%�Zmc�bZ�	���@z	��y�d豺���'E�Q�����:΁�-��>�=ҵ372����:��� �gA���9��x2��� ���f����Kf�-9SW^8�}sS��	��N�37����n C�����r��r�pB�Y�Ah�l��r��Yo9\.:k���'��2���<'��:r��4WO�`قqx]�<j
`j���,xc�YQ�Kvˇ;[o�v��c��W��2��X`�P`#�IwGG�d��X�d��d'���n��xsD�͕b�p�&[TKͼ^�Ӛ}�����)���nw;d�}6���+2*���O�u��3O���0��ߒ�X��WΧ��#Դ�����	��u��G��r���r�t�2L6g��B�y��ˏ��^���G4��Da�� ������C�kS���j�BQݼ�!T����3<�RG�jD����~z�(G�\7�0�}���糫a�d�O<d˶7y18�����2�:��AgF���5�)���s']�G3�`N�5um��N��,NC�Q���5SV�r�Չ?�S�����i��f^4����$6e�e-G�p8.@����y��Ց]Z\����DBD����qVzi�ݴ2�ҺN����EG�#:G�X�a��Ypٌ�#�y�Ï�C���v-��Sz�W~𥠁:������v�YF�����p��,�"+�3Y'D
��]��%�������!
]��27�9gϑ���qr>l1}9�og�ي�%O�����C<�����=݇�NKsh��8�����0 W&g��O�����V|R��8
��L\�c��xǂe�Msp�is
���i!��/�y�MqZ��f�ɐ����v�
�k�/���0g6U\]��zU�K��؉���)?���;��9�P�A���U��<�cn�*��^Q쮽�%:�qiՁ�H����S�
�-�>����
�t��ip�.��
�ŗ\��:���f �Z��n�N�6���@�j�U,����1^�i�1� +AM�f�t��z��ݓ���v���O�g�Y��z��2��T��A�R� �4𐜕&|{�����4W�m���X��W��h7C���̛,�ʢX
��<,�	0|�u��Rk��6���SVˣ̕�X��I%�&�<�.k%9�ڒ����I~/=,�Yu��	ST2%�:cš�uF���Y�j�J���\ƺ"������l<��9X���"�FB$���+�p�:~W�u0�������m�aJ��5�����ښ]����+mי��fl-�&����4��OL���+�AϪ�����.�}m�!5�rFj\N�����5N׆��O�\���������;��p�i�����[��/����}\#@߀��X�YM�W������t�ݷ	�|���S��=��3��ص<]�����ݪ��s�a�s04s���,W�`g������.�*��sICv#�H?ČԭH�k,��'tT^�$<�6�?�� �SKW��V�?��V�OWM�0716��%R�e|��Hg�F��\�)�͘Kj��ύ$GO�Ѓb���!�H��G��ϏNUNm߆���4�kB@��'"�-hW�-�	)�����3(��P� b���)�f*A�,��/¥M��q�޲0mi�J��s�Kz@���B��R{�/�Q5S-LU)�
�9�@�(�EW���8"Ώ�/�'`�%��53A� ��U��y��'I��IVJ�]����z\ ����r�z:��T^\��+d��������̎��w�SN��(3W�=���� 	ښ��8F�h��<�R��Ҟ�a?�Z��  ��3u��.nKE�:K�q6ۭ���É�w֥��m͗�1:xb����Ψ�XCtn����+6��>�ʐ�TK&��9c�D3e�\0Q(B�׋4�-nk��9��n��Z�t�9��9a̅א��.�N1cjW���E�_7&�`�C�`�`���k�~��ytq��У��b#�ɭ��k�m��IT���21U��dG\�I�&1�jq����`Nnq�5�9ґ�8��t\�V��L��bJNZl�Ț7e��,��^ `��U��/�S
�JY\�N��2���&�����L�� dk�u-��d�/J2��i5�\����*���9�}�����8e2��Ǻ]:$~�(���	In�|9P�o,f�����[���W��o��osuz�A:]�|�N���o#>��������wU9��6O���w�hI���c��Jg�ݹ+��Ң�s���.k�ck"7ژ��uȈ�3�:=�A����kg"�����Q��V���p�b��k�y�v�$��|
��%��!�$d�9'���� �rݸ$�̫.|����BT<Ǝ�������"�	s~�w�t0��P��]G,�4����P;9t쳣}�)���x�}�.
/pcD(1�]�R,��7J(˕o��q�a�+��x��?c�(<��]� "G��$Lqяk��;O���ጺlp��08E�y]��4~��	7�F���9u�8	j
�:ɥ���C�KF_��b��j�^I��kv��	9�������'�/ݗ&�+q���Ģ�2}Q+�"���*;=E-�,�&n��Xؾc+ωō�,#�JXI|3�!��&k�f�%뀗�����,8mYL��3k�V��vZ�k.�d��V�vr��P�DT�?_�1���|��t�S�==f��(���7����Qv����c����ϟ���r����=����7�o�3J�W�����k\�.����������qj¸���K�=|��B���iS�]7NJ�f�L��[_W#�/[d%-�],�aP3 ok3_�w��SA�
��?��-p�� �Q�<lr���c4�=\��a��-���'�C�+L�����O�A}ʯ�W�q����4I�U�����D����Y�s������b��ѬLCp�r�%@q�h2��0}/�Z����)���������������;�O�lh���k_�O�v�w�J5+o�PS�g�&�ꌂ��Ě@`)\n�o�L�|+A��h��D[.[�ř��:Z ����q���q����������j[��~AW�.�t���(�~��i�x_�o�b��&�M�����7�����T�>`�0^)a�)؟8�t�l2�i1�!��:�����T^���2���gÎ�Y�9?wSF�ٌ�����9§�l2�R�O��{�Z�1g�������tZ�B*�M�8?���2T�^z).��p�t��+��D�W�O�+��:[{޳�Nǅh<PB�q�&���h�^���}M8_�冚9�h<ҩnp�P[}.~� T�G�xOj�^$������Q�wn��^I��,ʭd��'	����o����{�G��x�����(��������>���n�Q���{��m}�o����V�<�����w���˽�WG��g�����~�����=���x���_�����g���ZN'������?j������q��q�v�����>�=���ox�a���j�fq�Y��%j{&����o�7�>}mo�3�8������7;G��}�ǘR1��J� �S(�̦��`R�C�~?�y����"�Yg���ڄR0S v�����'�ߎ}��L�k6��K�a�P��w�|h� ��O��'b(O�����blEO�`π5ʾ��"�v]�6��zx�+z��=�р�#?�a���}��C����~��݄��I2]�v�����A h���O�S�^w��7�ö7K¶��d�c�̟���Gv�KD�>f˟���������%;��awy�s<�]6�&>��|�Yhv��c�|@^@��'a�K���r�= xѐ�t���;��;���s LU J?j�3m��F��u-$2�8�&11�y��(%�����<pb�>[�`��
"��I�0�D�����c�S
��|���b>���8B/���g�s��L�$����� ��m<脀��P�6�P�`���G/nAóxv���Q�`8��jˍ��������S�܀���=lrJ؋�п�Nf������A���7[ǻ�o/^{�%L:MQ
�a}�vF�q 6��0HN���+*���!��<|�D ���$���!	��p��R �MԀ��l�l��5\ft�r;f�_<\�5
m{��`R��uͣ�
���2�d��K�>�8��'�Em1�O���B�m;�C|Z7������ա���3��<�s� FԠ����=8pg�P���&����b�j�p�X��J�g)����ښ\�֋�z���$����hv^�A�H��
�S��qǠj`�F�G�~�)�k�Jp�0b�b��8�����+���؊g��o!��Z����7_�c3z+������QQ;c���F��^��Oo�!��R�_���_�m�nF^*jb�u�w��9��<��#^b(,C_$	���u����8	��*	���Qm�
u�t؟g�|Șq�FU�hh���4e��\g�zC��B��d��n���|"�O�2�:d�(h�
�9�W�"���D�"����/-2t��?�ؐ@~�
��}p��#x���E�9�7>�y��ǵ��������2����f� ��b�������f��W��?��<<�l�0[�����ʠ��M�頖�F����a�^�)o^�SP���q���n�l	��o�7�{����j 	��-��>��k�죸+�AP�u音���@�n5Y���/(�LG2����T�r�(�F4���v��j��H��憎iu*	g�o�?�}t�*��E�KB�q�����@J�~K�i����9�x� ��r�r^��Ε��+�+VuwqVh*����w��Qp�tz�C��8��P��f�`���Ջu��m���r�,�F�в-��J�3$��Ȝ��
�4�LM���|������,��Sʹf�{��v��[�&WϞ��~�6/��`l�d+�	��:���J/����œ���:�"�^�H�0 u��:��`unV�!N�ώ�9�$"��79��:��`<��I0!�0���1HP$|Y�G8�(L|�:�� ���i�`%�}�W�$��7-�P�6��ł.mapl�����E ���'AX6�Q;\g=t�}aF�e �$0��"n�e����a�}��������ۣueX����<緡1���s_�I��(�����կc���wM�~L3��0Fn�E	rP�%�.�6W�]���E�ċ}����N������ǵ��L�b�(��{�乽����w����~9=��n*Iy�@qk7��� c��F�7��$J�KQ�7(�A��`A�͞��RP0s�gr�C�)�u��%��@R�����uaj�-V_{N����/Ujʤ/S�(4h(k��G4� 3ń� �*+V�ǲ���������>�$�;��%��Fғ��dm�Е3c�df˴�(���j]�EI ����n��!nH���v��]�x������2Dh���{��cF���a�>�=��-���DE{�=��L3����G�).!z�R\w��ʘ[c�+��VHI�jo �ė�Y ��B�=�N��f����љLĀor���Xp[
'�}���X�);�\���jˁ����l�*���0��7u���p����x1Q��A]��gy�m��������w��6��K]�;u�}>��)#-^��ftC��`r�3K|g|���,؃A���m��Pe����CX/X�ŀuq#�W�Ƞདྷ5jvJ҈�?��-�JS�㛀8�c��d���V:+0�����jx��t��J�/�o�?��"\bI _�I��=�ͱɤ���*�y_�[ܐ�[o�{�h����i��xd(.rv?�I36����Z'��?a�aȰ������%�,gO���2|a�����*�/�OL�!�Zn?����`�.�Y�gܡ
�F�-�w��%��т���(��yj��ǫ����m<��4w��s��=w��s��=w��s�����M��O  