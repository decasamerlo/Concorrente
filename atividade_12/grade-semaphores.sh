#!/bin/bash
# Usage: grade dir_or_archive [output]

# Default locale to UTF-8
if [ -z "$LANG" ]; then
   LANG=en_US.UTF-8
   export LANG=en_US.UTF-8
fi

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
  BASE=$(echo $(basename "$INFILE") | sed -E 's/^(.*)(\.(c|zip|rar|(tar\.)?(gz|bz2|xz)))$/\1/g')
  EXT=$(echo  $(basename "$INFILE") | sed -E 's/^(.*)(\.(c|zip|rar|(tar\.)?(gz|bz2|xz)))$/\2/g')
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
elif [ "$EXT" = ".rar" ]; then
  UNRAR_SCREWING_UP_UNICODE="/tmp/$BASE-test/unrar_workaround.rar"
  cp "$INFILE" "$UNRAR_SCREWING_UP_UNICODE"
  unrar x "$UNRAR_SCREWING_UP_UNICODE" || cleanup || exit 1
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
�      �<�v�F�~�W�a�R$x�d�X�bŢbmd�+�qv-�M
6�h@����9�0'{�����Ƕ��4@�bEv&3쓘@����]}SHYxF=�q&����z��T�r�����hm}��n�k��k�7/GRZ"�!�L�^9l:ܼ��&�}�e_�
>_�kkK�����e`��ȳB����y�_��������=Ҽ��g�s�?��8s�ƙ��Ko��_����{��N�U��;:�uZ�����R�x��l��~�g@ޒ2!u��4��&	ϩ�����> ek�j��D�E�Y0����<���^9!i�#~�*0T�	�t���A�U$�X2�M�I[��̉�lߣ�@]F��A��{�o��q����u'}���GO��V{}c-�������Fy�x�ٔ<e�����VI�
o���]�,[�!�ª��$��[�h>����Jlֈ#JH�s3�Pe�$�i��u`l�� �ұkZ
���T�s���z��p8!-�#�4�W؆7������Cx���_�(��Gr�C��J,c *��kf��'F���D�xZ�#z�<���V��#-Q�$� h�i�z��T����߯�*�����|�.���J�=GA��6��R�D⯑��<�#FC�a�4k�9?S+�R� �jŠ�� 	y��΂��Ѐ+
�:9i�����f!p�ONڛ�c��&A�/Z̿$>��b���[z����RO�U�j����:�$j�RVU�ߊ`�*����Gc `��pR#y�Żh�i/�L��I�����#���Z%�~j;�%��`&,E�Y�����TZ(״����T822�إ�$~z{�Ӫ�֬��]��f�/��iUT՝�T��j%/T��D��/����I�OJ��O�iV��z"��F]�ke|��τ�J%u���r��E�beq��i�+t�?��H�B�䤒 d��/����%ȡ'C�|5`�����1��쓣�D�u�L���>U��:�W5Y��6�P�5�RRxjCl:p<�':`7��J�S�.�V�Pt^Kǳ
yJ������E�f�#�t���Ezb��A˃~J�H��Mʳ&e����D�J3~/E�+�V?$�P*ړ,��ZP�ۨH:�F���Y������>}^���"%�4v:D4:o\��Q��~��^�`���_�o���`��!:��@���&H�aSIS9 �?��h$B�Xme��	d�����8_�"�{�֋��g�1���'R�riΝQH�qq�JE���#�
h�+�Q�^�y�z��~�)�oH<$����9b�� �����ˤf�ŀE�W M�ڕ��e��|����T0�4U�r3������$_r`�>�)R�>��ϛH����p��'c�@Z�:�i��ȵ��b�-CNS��N��I�Q���gHcT:�q�X�ȕ	Ӄ��sE�9�!rhP��ȁOl34ɥɸTC�B�$C9��b%�(�L�|�����ƌ���V@��Β�72C��M�t�6��tv'��Dcĉ��*��)�Z:2R�YH�k�'D��7��J�j3���6�#��C��&g�!a� Wc�m)�����Q'6I�uR+�g�<��J�ڄi��S:V���p�_99Y���0t�+�YE�NV�+�p	��)�����F}�C�|%�H>���
P�w�Ai�	F�q�[�1Uy	g��.�q����+��Y�B��fS���Uݭ��OW]UjWW+��`����7Q�[jKV��1����3(O��o	��6%���o�s �(�h��ҁ�76��#L�Ǎۙ��γW�/z��/R������i��t»�c��_�=�����l-���FQ��^����Nw���)�K�_�:�5���?<��S^/�v�;�n?��S�(����G�r\���IҰ�EË\�Tr�m�,��&�T2����	��t!;�P�S�!���d��R����hi�Oa��w��$�|�N���ޞ����q[N�؉L���'PŤ����ݎ����I�0aľ�A��R�ʌ�E�K阔�����W0���ў���� ��o
`%���|�3v���Q> P6����>n�0��؏,�0M�e�Vnx�Fn��D'[���� �>�N��tA��M�ؕ?���4� ~�vCE@�w���_�Be���W<����9J�A�u�7_K��M12)���W)D�s���g��x����"Zb�����S8��xE�_sP����,�>���w�Ǽ��q~��hmy��u�/}w��������?2Ɖ�v�����'�Ӕ=2$8�a���'c�k��5���
�t4J�3�z?�BD���]�rSP���P�Q_,���2�j�~�W�ߒ��_Na�"��e��JɎ���u�k�8�9ķ������a�A��s�gϞ=x��z�mp, �> -R����95m̶Z�$��Kb���� ݃�Eh:.��u=�]mU*q'�$����i��<�� ޓ�9�5��~���1_rK`�ģ���Z �	FHq�Jo^l�Q��:�4'��ϴ́6��e�3�q����jOB���g��r��8) ;���1X�b&�{���U�p���+����	v�`b2�}U	43_q��RJ�Ç��u4�������`U�%t�B~k��D����h5�{��.��V�\ӣ�3�Bm�e *�6.~��R@��h|�R���ߌ�ɜ]�� M��z���Ɖ�l6Õ�F�2����;dI����QB\�A��μ0ﮏ�����k����������R�F@�0W2��ǣ�&���F�`h��<'4�!�M�K!�҂{C���X����k@|�� 歡QM���B�R	a�d����rMƈb�r}g�&������ip�X��^���&��ۅ�F��c=�O� BƸ�����uN��9n̽�ZO6'r.�	�!5�����y�_2��=�qH��E�<q�vm��(��Ձ�+�����+v=��Ķ���S��(����Ã��i(��X�P�������8q@�s�^�$�)5@FW[A>q���������{���n)}*!�Ȁ�C{�ut6rB0>yr�P��i����E���mL�R�0�έ��NU��fS�˽����ĸԈ��XD�)�4���Uq@=�;���,���F��Tl�	��!z�P/��,��y�l.h4�M��C���%�X�s5��7���n��_���\���3-E�~w����>��X�X�eF���b���t9�;��/�;��#�s]:4�c�\T�����$t��H%�$F�W!�E�Џ R#\�����!������ ��������a�+$D--�(��뚁{}$)����R^t��3ʸuXI���ў#H�12��$"��}Pŗ�o�b�3��+
�
����{�Q�2����ip���9�m@��_�[���:�K�������J�S��M x�E��9 Ư��G�~l:�o�|��0j�R#�{`���� ��P�Ɵl/_}��E�A��i�.�qI"J�p�=�ȁzr�]l�e�ܖb�R��_�M�� p[g��YU ��SOZ��Ak"	?6G�#�%�n˷�WX
�n9ϧ��ݢ�z�op?-�he��ϓq���9���wh�_�����T�������_��JM�r�k�s��N�yJZ��ӲӐ��d�r�J;��0m���'UWٯ�"0�,��5�z���"��}��ZS����tl 2�ʀ�Vc�#F��w�	�p�t%��[ӽ���E �9�5�[qO���� ��H�ŝ�5{� ���'E�����Ԯ��w�7��4��+Qi��ޅc�&ûF&n�簸��n���P��چ�v|F+�ȼ�ۜw�:g(��
U	8�	p-$H�w�b����J۞�EF�T�:�m���S�I��fK4�1��
���9����k]���>�|��ӳ1�n�9:�������D^5>�y�
�@Pxƙ���$2f�2݋S����s����._`��NX6����d����W�S�DA�~�i���5�0�4�s,3�,�s��"�U]R¿��	��3�7K^�vD�Y4�!d�|Qcm��S0�]��&+z��̶���hD`���S{���@�(����ix�(���|�+�ya:�y��W⎊�s�*i�N�c��N2��2H�	���S�~�N5����E��M	
��$a��}��%&fx�+	}���4_��#.�3>j�^`^�1?D�7�ߺ�_2�m
���d�����.^��* &�3����4� >����F4�q�E� ������9g9O���W �x����zț�z0�ѧz��gC¿��4��zW��X��Xf��2o�-b�r�~�}�����x�LLW��W����-�csZ��q��>w���"��lޡG6�UѮJ��}�nFC�E����`���g�ã&���+E�Nx-����>^xMF�E,t�N\��làg����Br�p�����W�����q�^m�0!7s�y~���K���l �j��aH���Z������VV(�:�dA���&;��[b��b)Q�Y�{$���'�h���t�uu��bӌ�8�;��ٵ�������� �
 T蘤5��R ���B��c�����qs���?n����������W)���&�Q��$5�*?BX`5���o����g�@C���}�]�&Vt��}l�����\��w�'>e����zr�7��M�g�M̔�p},�a��хߺy��A^K�Օ��K�S�P����F!��u>�m�z%�|�ȏ������H�Cx�7F��Cz�^ܡ,�_��ǽ�+�(+�?���XG�^��ML�V�wӄ�ip%6�j�1��*~i	.o�`�@r��#z~�X��V�V2}>�om�X��8��p��1K��-�	�f!�Å�U%d����.$�p9[z��_7�a,H~�F�H^Ȯ+v$�R|��X$�	���Z&l��w�`�Bo�nb�C~��/n�4ɖ�>���P�2_��Av�F��uZ�R*���?�'��K��,{�[af���{gڏj�؈<ѵM"���Wwړă�%y��ȷ�c��o�i%I���50�=�w6Jݣ#�����?�4K���z�݁'���!�oa�E8��k`�z����^����R|�5.�`Ǩ����K��]�4��L�]���{B$��Z�R�<f��M�1I �����t�>E8%��i�Z��-�,$�\G$+�
�dt%!�.�'%\�*8w�bX���-���6`���E�5�.�ĉH�j�̻��&�	e��H5q)Pk�����e.�:�Qm�q�JC|�h�n����\�ޛ��V��qgzrWs��2W�XUސ���T�n4��OW���+��D'����J�J*}���	�Q�*uCV�5����n},�Q_���l�$�z�O�	)l�{�L�ր�e��Kaw�֟d]��|g���#<yeQ��)n��үen~'	L�M�s�m�m\��?�a�@�%y�S�ɶ��"�j�D8]^e\�eY�eY�eY�eY�eY�eY�eY�������� x  