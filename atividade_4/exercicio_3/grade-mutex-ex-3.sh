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
�      �<�v�8�y�W �㐲d�|I얻ݶ��i���ʤ��Z�,N$�!)��n̞}�������x������1��IU�B�P( �4�/�77}�Ԅ�������zS}����Yאָ��w:����Zs�Y�z,�i�NH�#gBoܨnQ���'���$�*Z�������-R���C'��f� v}����6Z���X[o?"���~~�7��'��׸p�q����7�'}���a��Ԫ�<x{��*#?$#wB�둥��Я��)Yb �N?�&9�&�zP&J���,�T5B�`��%���<?&#��ƍI�}�\�@�@Q=g�93NL��a	n1i�M�\c	�+��:�(��"hVX����{Ns����^��1��x��d����͍���-��LfCJ���믎w*jV�z�ټ�Ľ��BzIo0��z1	o�?`L�����d�52�%&��V�ڮ�W�m��
8�@AL��B-�5U%��m?�^,(\�nL���Qcz�8i긞�/Nx9H*��+��&�����q�td&� ��G��.r.�y��� g�Qc�N��P��
i<=��9�^0@ÐtI��#���p@�G�k�
")Nld_ɛa�i����QP��&9VH��5"���)�F46��bҬ�����#�Y��ejŠ�� 	{�e��¸�0�U�uvֲm�Z��]�Fೳ�6e�K@;��f��6��dp���L��٪��M�g2�,�"�Y��έ�[KҊJ��g	t�@�J�ty � 3>�IKj$�0��|5n���ad�ÿ�~��6?՝T�YN�09MI��)��wA�J5��[uE*a�#9���~z��y��ݭ�g��®�WyfQ��Y���X9��������j��%�I�R�!��Q&`��o'bf�a>0��V&�e�z&�YV:�/��'�	u�YP�YLi2���}b���/��LE�N_W�i=�*����b�[���>��\쓷�����*�c�}�0$��'U�E����K���۔�А!�����;�'+�I:I��-��k�,f��H��ݙ�������&���.5E�ũʃz*�H_Mȳ&d�����׀!��x���J��<�L����aR��G%���9��tش�I�l�w�y~�t6�#�Wvz�dL������+��K�w����?�z��z���!9��8 �H��Y�NaSqN9; a_�F�4�I��4'6GL qO�^rᅹg�{��53?Y`[�H�ʤ�p!ڍ[U2B+2�f�p`���Ĉ��(`��I���Re�<��`�.�1R��dB �����2hň�E֗M䈽+���Q��������в4�nej�aI'5��=�h0�#�6B��'��y˧¾6�Vbq�6��f�Z�i����&C�+���f�%b�y��I4��	+}<b2��N~�{&��rifz4�̢����!q@��r䓡;�ډ�Tch��|�2�g���Q�#E.P�ٗ�?"f�;!��hv�����Xoe*�R��5�(�J��ޝ��:�ؐ�lB
\5�!b��MVVT�U�i4`n�-�8sC:$�b����9�v��D1���T��uR-c�kb����aq0N�?�Ր�����g�b����hV���g�g�9��ݕ���)����S����͌|��-��,� E�ig*�7�Ń��(R%������"�'k��7؝�C<���$m�l�6bge����w]�nWV,�0������JI���1鲄�D���l�Ay�c�&�'��ֲc��P@�E%�kf^���'	��)��6�!�\���}A��Wo�~�����!�_;n|u,8�k�s��������H��ߛ�}<����w�K����~w��_���Wݥ���^o��ݽ��K�TR���$s���$i�UÛM&��čb{H���.|�+brK
�3��N�!��K&�u��K�� �PE�@�
�8~㑟DHN��� ��ٞ8���
��1�O"�<�9R���v w��}YdwoH���#���҈~$K�3�h4�4 K�����OP��t���5�~ �3a	����ry���^�	��)eS�:���㕈̦$�guu�r���/=�Ͱ���Dbwb\���?&lP�?�.Ȝ���*���?�	�t�-`>�;H���\����J���D��V(�|�?��7�Iy[!���Ԥ�Y�D`E7�#2�+�##G���t�|H/����~�VF.!����>��˧��4�>��%E�g3;�ol�=��|�����Wow�{��>��6��+��f��Pz�Ip��n�G��`���k�a�+4T��dF�/���y�n�J݁�8�_jr.m\Ɋl���&1����m��l��������E�Ѽ3�U��K�a���X�?�^ه�\�z��{c��~��ɓ'K�-���	g ��G�E��-�Sg��V�J t�56��M0 ���*bǝ �ʒiJؕ�e�J�,��}뼺���� ��Ђ�U*)a1C�K(���`ͥ�̾�Z��	��qF*���P��/o�v��Od,�`hm�~Zcr���A��P�y��	~c����e�EM��1�\Òpjq2*����\s�`$z]UH|��"�\./󖬡:%m��o�F�V9�P=����$g�����̨V�-��L���04=���nC*#�b:�mP<��1g;��.-�Wa�g7œ�jE@��#Ϣ��j��h\>����ʃ�!R:�_9w��~XO�V��R���?X�o���ڭ���[�'���������������I�����O�O�]y�N��=:�	����B\�xAv��h�_�x�m�gJB��ʕ��Oq�2���荦��	��^s��.`�gx蜇��U�9��Ga��D�$�,�'@��� fKcXt�(��kv���c�f^�^z`�RR�(~`fȃ ��9����F�>���>XTX�er{���NgrO^�vA��#,0Y�%<kl�[� +�;��ʾr��I�*�$l<zf_1�m7s<������7��U���#gL�d������iVHՒϱ�"$U�/�y6۳a�7���2�j��NU�y���f5p������Uk�`j��J6t������Ι_�G�2����p�Y�/��qhTKMN��0��O�?������Zn���z���&i�4�D0,�/�@���^' ��L������7u�q�S�@#�������iR�qt��{'|�RsWb���V��כ��Ha8���`N;<�UW�pB6��B����>,�L�!5��Y`UVT��s�}����Q������#��b�=<)�~�N�3�
�1F!I1��@@�SX����<1���+�*��N��ڵ]*��̛G%��
�f�J�)��{�u���;{ac�g'��a[���{R�����yi��oWnu?r�o��VNXw�Yp��!Cu�	�������D�)�5�����4�W��A�5H���RI���C#��Pg%�
%QNB��y'��k����w"�ؓ���1@UB?�h�Ν[y1�i�B.6��T��Q�fBZ�3�i�[1RI6V|��ZQ��HE��)X8�R�z"I�+�&�2�~��Oȼ�+�'���Ci�`tߐ0 Ñ]�QI�\1�4-�dߓ&ْju[��LV��͉��b˫(b?+�4T1�%��_D'c�i&��G�~�rŬ"$����$k���gY���Ijkk\��=ȷyP�4-I-,�t�
�z뜇nyZ� ,��DH�@Yiiq��<!��IEVD�9�����xyS/G{P2B���E++eZ�%���.�����s���a>�&*�=&o�����\����Ǚ{�j�x�+*X��8lІL�����h.���ڡrw% �J*�S�9ÑƷ��I��6ωS^h�e��L���O�������Hcɘ��6�Ձ�V���V��d�Sc
�ڀ�m1=ʻܶ2h#���d)I.y<G�d�r.�ש��-�d�NT��zc�п1�F�8%|qZ5Y�S��ny������r	��Dn%{s��.x�q��i�">>ocq.3�.����%���c���������^� Jܼt��"Y��g�-C�@y��}�x�������Q (X�a2V�+�����w���*`��1p��=xX
��]�q�jm�|e�'Eu(�|z:�^���ն�%*p]�-1|Ex+��\��ui�v��{�`/ZpT�ueU��*�=��������ִ�<�u�O�w��{Q?d�X�����G�?����B���č��>�; �D�,Ro��{D;���ߝ jA ; ��[��e��L�n(�^���0���?�sch��"�t8gQS��j&�P���\��:帣0�_H>v��U�	V��d����}�X�T�S?�}�!�Ԟ3�R�)<~��P8����rD&���]s�1Y���j:����f�E����I�ru�?������B�q�	)��!�|��xY&ڪ�pyqs�Ydz�;f�Ͼ����M���N��j�F���N=��v�F6W[����{���kdmu��:>֛-|�_l⣵�&H��6� �Y}�i���z��7��wV7�o�������Xo��!�v�+����\��%���ɟ�*1C��u����I�׫���:�Xs���t��]yB�]���X����0������V(ipijԣᝉG�rZ�_�}p0�8���Wˮ�}�&����4"j��&f^U�
��Fz�3����	�Ps]�D-:�ʞ`%�򊝆?l�'n����O����V�h���TҁP3�;�V�N�B����j��c��r�Wg����E���ճp�ؖp�A�n�\�[���f��_m��dؚ=ND������.�poJq$����ۆI�Z=�w����z�]6���C�r�~֮6%��;���kι�@"��
�l��[�K���PB&S+X�J:�&`Mv���{:�����Sǂ����F'{���|���&�(�/9&.�� *%��J�`L��qJ,��/'d��.*���� k0�ٹ�Eθ����1d�	�Mo�/����� _XZ0*f��?�~��v��y&7���"v�;���k�Ni:ӝ��hb�6zJ5vڋ�k9l��߉C��#H$����EC�\�ĺ���R0��v9�<�w��w�ϑHE�E$n�TFBv�A6�͝��{�DU��DI,~q[!�d�bZTP�
�w��<�r0m\����8h�u�:[
��O��z����o��1=(2O�"	LBk&�3�(M�u�ΐ���\���$v�]$��N�] �#*N*\<6F���a���V� ��~�_4V�E��}?a)7��0,
}U����|-��d�����Ա��k��s�������'d��t;�'��t��ol����q?؜:�>�׉�8�)���
1���kg`U�{��^��o�lu������я�d���7��#������.^��/����@=�*lT*� xӷ�Wݻ2Ro �c����w����L���),� �3�:~X�~�r����N9��� �8�;�M����ۇ� V���3��d�@�Z���n�]r�����@��D���_]s��7�&����xUa��a���l��J�Z�}'�v�"f����<B~Q���^�tm��I����M���sb�9>9��޳O�߽��u������<⢶#�}��W��o����{Z�/����^��(���"����z���/]���,ڞ<�PC33&-�C��QU��tV��ܵ'3��(���"p���l��<�AN����^�xkj>Ɓ��+["0�c0Hl[D�� "���&��.��2�~{�ꄗՆ�~oTq��������+n#��֯h�ؙ�� ;���,�p/p��$;G�P<�f%N��c�i����s�V�C�P�1xBb��3R���������H��f�hp@�]�W�@�Mb��|F�,�S	�pq�:�i��/��:�,�������BH��4-",mN	U����=>>�����&.�`���Z��0 LX�|У�1W$Zv(�%ذ���J��5ę�e����$[^�PA�C��ك���",G'�OA��cv�Q�(CT��ž�ZX�44��f��P��d�(;B=K�T'[Ae���L`$�,G�U~����R�n"*"y6�l��O�_������\�?X���wRloي�PV���|�.<�
X���8!N�}�¬��Uþ8TжBl}=8�����5���었^^+�"����3�/���d{�i��J.��B��0|()շ���'M
}QiNhE��V�"\HC�����Y���L����D�*^t �ި�$/ ��@�i>G��I[/t��wr)���U�,�h�Z�"RUW���3��Ǿ(Q�8H���hq<� ��t���b���~��5t���Ƌ�ho�C��Bx��t�k��S���}j��sm�}틁hc4���k/�*$?�"o^,�xJK<�����]0��'���2�ϒq7N4����m.���N���I���
���Jm���$7��T
�.�uFc��!C�O�w�[���O������o��/� �dG�ћ&q:�cT�ѯ&�R��x*t�E+}�؝��8�.@�x�Pf֕�F���$�h�<�l�t7�V�Z�������,�����j��D��J�@-�(u	���78��ԏv�	�L5(F�C���L9����� z�(�E��C�mr��tfƠ�?�K���n�����/&0wca��c0�[��B$3��s����"0`��UK�q�Ҕr�{��'��j���N����9�3�F5\�d72�Qi�����zt_��=ģ�s��^)ylf�9X���I��
�e g&�D�� ��~6'���S+X���zk��YzŐ(�W͡�?s��,=�̡+�l��UK�f�Q�m�/�.e�4�I��y4�3�b����ǠnW�J��B��Q���$5o��LSn�MsaQ�~3h�a&!#�k_�}�g�2�l��i<AV7&��i�`C��0�w�064��Sx��jɽ
�*�1k_3+YL^�i�p'�ۚ�X	wh[�Y�3�q���ζL9�˨�N݋Ke��ylB���Uv��5O�[��ƞI��n�gAwc��ڭkOTzw�fezqM��h]�Vk6���j7JĠЭ��B�l�rieSЖV�u5*����-�5O���/*�H�G.݄mg�D;��fp����I��"bO+f�3�_�xv�Z��ٴV��4� F�l��6Q )����:b4��ֈ<�(o���&�lcg����k_�+�僾-�*��3·���>_�: 2�{���_�U[l�?z�?;O�Q~gh���/v��w��{rz|�����.�0� ���HFq�x+�΋��������aD��!`L����<Mo�;�0M��K�/�i3)����I�{|�5�x�p�ش��L{��A^'����������m:t�v�ERv��V9��ˡA�R�\�q ��\�0!�K#D�e@tHuٸ��� er�e.��@�u�H�}Z���N�F��4��&�>n&�9�<�6{'��=:avȒ5^��?�-�/T���	�r�\<����+�օёb뽎�������c�İ'�T�.Ea��;4gr{S������l}+|���.��� ��Ū�Os+���;�	xL�n_��-�a��M0���k�'n��%������'{_��9jay]��c��cÑ��v�~8��o�����l��!�m6yr��li�J9QT�,��VѨ%ٗ}�#�F���]A�_�z;y��c	�
���M|&�F�8�`�.CD_���Tc�v��t��
�FO����&�z� �}@���)�B��!��p�`�9����/~�i�<��u�37��<�X·$�fA�b��,2�2U�L��j���\Gemq��)�X�UD�F�K�`x�e)vj�ĮǕ�]�"�CN�%c�Ǭl�jY�A��+CE�R	Pښ4�Hc� �ʄBGU���/I�ʊ��2�J+ŗ��X;�2�Uᚑ����z�z�	c�.��{1u�&þ�Eg3"\;��q�f�-��hU�#�?E��y3�;��J�6���1	0	*�U��R-���� �4�.%���BfNe��*?H[汭���B��jNe���!`YC����kU~��,�*���|J2���*�LW'D
��u(u+>�$�;�#O�E{h���/�rc?X��]2
F.H/Gm�n�U�m6SP�E����1��F��F��)>l�Zv�ǈC� �<G��^T$�h|�o3�X2��	J�K�+��1{U~�Br����%��@WT�6���
�&�n����.�y�I�W�s3��]v$�c�7I��c��?�޽�:�e��V���r줞U��;{��+ڒ�AY��Ҭ�w�YɷW�nM�23D�'^��/�<C�b��~vR>��1�%�������BG�9<C��L{��C긮���l�a!|�"�lI൰E5x�5֤�T��
�MxQ��z?T�~��������A�X|��,SY5au͏��AIm6�1)��jS3�e��A�k[<��e�VU�,�U��xRø��j�7W4�����j	i����VZ���f�^K?N2q��{e�m�v���I�>t[��Ԟ�����a9O��b�__��)t�6{粍�z�˅�Ht1Զ�6�m&ƣ
��S9��ƕS�G�x���Y�nL���HG��K:mӪ�tZx��I���Z�����tel��X�ix�$̇c�aF-�!����hX��~��|k!^o1���{u�W����5�}�,�ʶo���lך|@iM�(jMĻVwS�V@�r0%�H��j.�"��Nߪ'��i\��B�&g��k�	ns��?��^�*��,��`�Y���Z�q�%�8��N�͝X4��7�=�]9g��|.�N���m�H̰՜��	�6߲\͎_Vh����G����0��^�+׵���2�%o��m���,��㛻���ln� �W���R���o����4D��a�2^�U�0|�oq��'���.��`�"^�7�YT�g*w�G
��ꬪJ[����,PͿ��y�R���+��f�a
�Cb`5�L��S��Ç$���Cqrsl|ެs��DLa���"���O�F�;�����^�i4�j�S��1	�+0'�,Jo/Mc�ʍ��/ �r��60m+��R�;2�2��'㭱d�Tj^�&��D50��āO.ˋ��+��_Փ���6�ؕ(e��#Eg���E=��������
V,�ć�&yƬ\�Dd��致��U|g���q����ff7�C�6=��A�?a����,ͨO�)4kkԜ�-t�P��:r�R����BPa@q��p +4y3���KezU��Z��;�:�|�.�<�Q��?�_����B�5UB��`5ֱ�)� �
�h"� 3�ŉ��H�
9���bR���~�L��b����L<z�J�wɏ��*`
*|A]X	��	+팶\X8S_��TG�ZJ8m��!�d3�}%܉���ɕ��y�����񃩜� y���� ?b!5U�W�jp�+�X^��|��8�t���a�a��!����zb׋�;�2h3��=�Β��5'�����e�eA5�G��4(P=D����� 3E�!_8C�f�p�12]�k���é�R�a���ەLJ�՜G�6��2LM�Ԡ�g��,�KP3/>��aEt��qwl��Wq��Hm��ӽ�ݝ×��p�?}��ыsB���&�J�Ʋ��|�r���s�N�1G�;�í�[{/����n3�`qV��,� �pX�<3���;��%^8��4��,h����FBoLYhg�@��s�2�EG�ռ+Ox�8׎5ó���h{}�|\��%C[��d)����T�Ἠ�X������o|�;�J��[��3�B��(����,�}��7��U4 �]U��h� 9q�p.�Ѩ��K<Į���WZ�89����p��|���L�����1��P�I=�Z��"�,[o5�SЏCrrȎ�Yp'��O}*��+<*�Bl�����qJ��c�(��[���"��dG1��@�h��Q���iOlh��kn� ��hJ�lx��ȿ�x�]���,x�����NDP;(��3��9)�������S#�*f_Ӗb��s�bX(�[�1�WT�����[� /���:�ss���S�gŢ��\Y+�f���:��e-�Ǫ�&��ۢ�}�;��w�eU�x��׽̊�H��lDo�b7�Z�W�˜�l�*�X���KS����Xy���½(�,V�[�y ��P�ʗ��VE?SٳB�ˢ]��������;���F����k����|������(���A#l� ��Я��g%���+�"��U{�ʒ*���ɟ
3I5Wh�`�R����O�UNx}q ۴U�R�䫬dU�ʤ5b��m�����^��\!c?�~x�
�x�@`J[Ec�J��A��l76��������P���̂2!�t�G�e�����=�gW3QnIe�wT�v����be���W�꘳ׂC������K�" ��>Z4_Be�&���U��l��.�S����� \����o���W���I)��W����W�&������cdE��c����3��S]t���ejX��;k��U��R 9k� ��ג�N�F����l�:O�C�z^]	�,/�dL�;�6�+{���Y;y��s:OA���3�Y�!��E���
�\�hr
����П����4�\��e=�R��>�C���7w�u�b6yo����c�˜}�kr9z����0u��њ��!��OLBpҾ���(���4)A�R��н� -1�V:TMV�M�;�jc/Z-=7�@�>��S/�Ř���c1*�yC6V����+�d��=雕����2��O,�a�>�Z�횻�
�o(��.�pSZC�:
��^7Sȣ;=U�֣Gl$~/cX�<v����+�yf���܊�����Y�CM6��[>��ŽF��&S����ۨ������'�kO��]���O�)r���t�mT��Us��>�t1����䄉's2�+���A؛����n�4��9ح�����*d4G�|N���o�b>/PCe�K�~�8�;�6&���`2�	z�z����Yk�G��Uo8�uBS��m�O��^\����MI�\>���m42�'�^��q��@7��C���5�D�����!�O1�F� ��n~�/�d�b��`D3~�ߊ��	���عp <������]}�����&���ᨯ?ʞι��YÛ}��9{S�}c�F:d`̳ Q-��/�^�)�G��-����SG���8<��G�w-a�OC�K�X/�Ƣ��X�O���2o��U1��}�sV�0�+��6D�,�&:���'q	��ȣOG��l�莼*1҄O��_L��M��x3�������s�|�}�0��Ľ��7Y烅�92l:��6���_-�h���W�W�M�J�m
�_W�נ�*M�_�CA�����I~�L�&W H�LY�Y6����+9���&������O?.����r�?��'��.���ޙ�������oxu�D 4W5>"�%?�ԃI��8�b$@bu���>��<=zy�ɽ��S�yW�p:��}��Ϳ]*��4�6�
5�,�?;!��ҏ&>~�' 4'1���3��h�����]!�.T����ą* ����=q�#|�ڞ�c�3$�i�QH���P�����j�I��=}H��D؍)�h6�=�Ȫs�~�C7$�4��}�(���M�Ϝ�����[�����N��8�p��yL֞��O�ڟ�ڟ��*y���l./�1Rv��,���]'�W��1%J3�3n"Ҝ^2��+o��	�`�H݅8~��Ko#:/�_-����O>���|�����Rn����E� N�}_h��,zz����|��3�wB���2{�E�'kŠ�&�+�#E_�!�ځb���[����<X�֤M,��f7��0w�
�	��f����67T�6Y���Sq��dS?���LA�Z�3R��ֶ[�E])!�$%����8���"�Ж��F��_[������'��e�����M�9K:;��Ó��ۃ�×�ۻ�뫫Z��>�\���*(���/�\n���_a���d����c�0��'.&sz�m��Q�7?+��!��ϡ~�ξ���[
�����rgg��ދݓM�@wT�GS�W�/��j�ăQ���������W��w�d�M�M�� 1+\vɾ��^'��0I�I0�m�F�������c{C@q���cRi&�.��Q;�$S�z��H� ����m�:௛_A��ǣ�_@ɆO02;\�ۄ�|�řF�����BB���.t7r��nA��4�l�z�O7pG�d�� �zio���O�]���u�iu8��Ꮭ/1�f^�䈏��)�t�������9���Qoy�{:bC6tCpF:&h��C²��o�0��{i�0<�\n�@C7�)7l9_�n���/�c��i����䪠l��H���J`�2j"�h(N����u���MrV,N�#LUc����h4������6ZL8��#�"����b:2q�dz���`��xЍ �W@�Wd�����6����������g�#�#��`Ʀ��f��� /ҙ��&����q���<͌sh�㭣���/�O�_P���C7%���k!;ll:�X�&�&ɹ��|N+~�s�� �#4�q%����%���	v�3�1�d���io��Nw�Oww�
.S�b�t�����ViǍ_��s�ɚG�deJ�V��y�t���|7�]zV#^����`��ՆΘ5�$�5����J:�9.3渄��/0�ܹ������@�Zn�#�B۝����.��~����R��{�	K_"ia����W���rS����d ���;�	�.�nJ��;���(�@h�>T�5AH*ߥ�'���7g���=�����7��ֆ1�|��Q:�͗���"�� 3y��.����d�"lD@�o���6`�e��'������&�����CLm��1I�����(�pq�2	Ef֟(�@E*U��oS*|�bƖ6��X� .d�K,e]��LfQ�Ն2�]��V�QTD<b`�I�h�����a����%�9���D_�Ќ8���'Vd����G>��x��~�>�nk<�B`1��E���{�#��u^�w�7���m.ì{=j5(`�Y��4T0<�dM>�:�|o��x���l	[,>���b6[L�N�:�D�9�J`LX�
�����#vs�L�����%d�>%�:���!��� R�US^Y�E��O:�(�)��Գ�w������|����=��#m��H&p٢�����N~ �����Ǌ�#����i4y��W��'7�� ���$���Iڱ����DJo~M�I��-C�s�����>�Kd��:Cu)y�R"_�S�癦&�[r�%P���gR�w]�4C�s�,���5��?G���\l[�{�a5�ce��pe�}���}��4�.�������}�@Ĩ�Dͯ� 	]i$�}5�p���J'���7`\=�dm�;�u�'���FO��Ro�{_KՃ<���
��1>Iȷt@$ݨ����Z�t����olY�Dh��֑�Ɯw��/�t�]���`�3?��a����A1�e5���i =��� ����l��������2���b�k, �^xi�4�+�d���&A�le�v�A��{|�*�H
v��]4M����L7��n��<ِ�qj�7Tc��i��}A'��R���_���v-�~B-��(An��)RP��3R��T�7SxQC>s����a���ｿ�(��(��(��(��(��(��(��(��(��(��(��(��(��(��(�r����� @ 