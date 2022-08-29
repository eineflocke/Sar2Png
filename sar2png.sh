#!/bin/bash -u

if [ $# -eq 0 ]; then
  cat << EOF
sar2png.sh: makes sar results into time-series png images
usage: $0 {0, 1, 3, 6, 24, 72, 168, 672, 840} [...]
e.g. : $0 1 24 840 (for sampling data & drawing 1, 24 and 840-hour charts)
       $0 0        (for just sampling data)
EOF
  exit 0
fi

hourbacks="$*"

### user settings ###

# elements for sampling and drawing charts (sar letter, F for df, M for free)
elems='u q M S F d n'

# server name displayed
servername="$(hostname | cut -d'.' -f1)"
# sar logging directory
sardir='/var/log/sa'
# network interface name on sar -n DEV
nw_iface='eth0'
# disk device name on sar -d
disk_dev='dev253-0'
# disk filesystem on df
df_mount='/'

# directory/path for the result image
resultdir="${HOME}/public_html/log"
resultpath="${resultdir}/_sar.png"

# directory for working
workdir="${resultdir}/sar2png"

### preparation ###

mkdir -p ${resultdir} ${workdir}
cd ${workdir}

gnupre="gnu.$$."

gnudatapre="${gnupre}data"
gnucmd="${gnupre}cmd.txt"
gnucmdtemplate="${gnupre}cmdtemplate.txt"
gnutemp="${gnupre}temp.txt"
gnuprint="${gnupre}print.txt"

find . -name 'gnu.*' -maxdepth 1 -mtime +1 -delete
find . -name '?_20??????.txt' -maxdepth 1 -mtime +36 -delete

### text-dumping sar ###

for e in ${elems}; do

  Fhms=$(date +'%H:%M:%S')
  Fymd=$(date -d '1 minute ago' +'%Y%m%d')

  if [ "${e}" = 'F' ]; then
    echo "${Fhms} $(df ${df_mount} | tail -n 1)" >> F_${Fymd}.txt
    continue
  fi

  if [ "${e}" = 'M' ]; then
    echo "${Fhms} $(free | head -n 2 | tail -n 1 | xargs)" >> M_${Fymd}.txt
    continue
  fi

  for dback in $(seq 0 28); do

    ymd="$(date -d "${dback} days ago" +%Y%m%d)"
    sardump="${e}_${ymd}.txt"

    [ ${dback} -ge 2 ] && [ -f ${sardump} ] && continue

    d2="$(echo ${ymd} | cut -c7-8)"
    sarpath="${sardir}/sa${d2}"

    [ ! -f ${sarpath} ] && continue

    opt=''
    [ "${e}" = 'n' ] && opt='DEV'

    LC_ALL=C sar -f ${sarpath} -${e} ${opt} > ${sardump}

    if [ "${e}" = 'n' ]; then
      grep ${nw_iface} ${sardump} > ${sardump}.tmp
      mv -f ${sardump}.tmp ${sardump}
    fi

    if [ "${e}" = 'd' ]; then
      grep ${disk_dev} ${sardump} > ${sardump}.tmp
      mv -f ${sardump}.tmp ${sardump}
    fi

  done # for dback

done # for e

[ "${hourbacks}" = '0' ] && exit 0

### drawing ###

for hourback in ${hourbacks}; do

  case ${hourback} in
      1 ) secover=600;   backsuf='1-hour'; xtic='%H:%M';;
      3 ) secover=1800;  backsuf='3-hour'; xtic='%H:%M';;
      6 ) secover=3600;  backsuf='6-hour'; xtic='%H:%M';;
     24 ) secover=14400; backsuf='1-day';  xtic='%dT%H';;
     72 ) secover=43200; backsuf='3-day';  xtic='%dT%H';;
    168 ) secover=86400; backsuf='1-week'; xtic='%m-%d';;
    672 ) secover=86400; backsuf='4-week'; xtic='%m-%d';;
    840 ) secover=86400; backsuf='5-week'; xtic='%m-%d';;
      * ) echo "invalid arg?: ${hourback}"; exit 1;;
  esac

  : ${datenow:=$(date +'%Y-%m-%dT%H:%M')}
  unixnow=$(date -d "${datenow}" +%s)

  unixmax=$(((unixnow / secover) * secover + secover))
  unixmin=$((unixmax - hourback * 3600 - secover))

  xmax="$(date -d "@${unixmax}" +'%Y-%m-%dT%H:%M')"
  xmin="$(date -d "@${unixmin}" +'%Y-%m-%dT%H:%M')"

  ymdmax=$(date -d "${xmax}" +'%Y%m%d')

  ymdminminus=''
  if [ $(echo ${xmin} | cut -d'T' -f2) = "00:00" ]; then
    ymdminminus='1 day ago '
  fi
  ymdmin=$(date -d "${ymdminminus}${xmin}" +'%Y%m%d')

  pngs=""

  for e in ${elems}; do

    case ${e} in

      # 'sar letter' )
      #   single element per letter:
      #     et='chart title';
      #     eu='unit displayed';
      #     es=y-axis maximum softlimit ('' for auto);
      #     eh=y-axis maximum hardlimit ('' for auto);
      #   can be multiple elements per letter:
      #     eas=('awk col. number');
      #     ens=('element name displayed');
      #     ecs=('fill color');;

      'u' )
        et='cpu'; eu='[%]';
        es=100; eh='';
        eas=('($3+$5)' '$5'); ens=('user' 'sys'); ecs=('#e69f00' '#56b4e9');;

      'q' )
        et='loadavg'; eu='[]';
        es=0.1; eh='';
        eas=('$4' '$6'); ens=('1min' '15min'); ecs=('#009e73' '#f0e442');;

      'd' )
        et="disk:${disk_dev}"; eu='[MiB/s]';
        es=0.1; eh='';
        eas=('$4' '$5'); ens=('read' 'write'); ecs=('#0072b2' '#d55e00');;

      'r' )
        et='mem'; eu='[GiB]';
        es=2.5; eh='';
        eas=('($2+$3)' '$3'); ens=('free' 'used'); ecs=('#e5bad2' '#cc79a7');;

      'S' )
        et='memswap'; eu='[GiB]';
        es=5; eh='';
        eas=('($2+$3)' '$3'); ens=('free' 'used'); ecs=('#d2bae5' '#a779cc');;

      'n' )
        et="nw:${nw_iface}"; eu='[MiB/s]';
        es=0.1; eh='';
        eas=('$5' '$6'); ens=('receive' 'transfer'); ecs=('#666666' '#e69f00');;

      'F' )
        et="df:${df_mount}"; eu='[GiB]';
        es=250; eh='';
        eas=('$3' '$4'); ens=('free' 'used'); ecs=('#a9d9f4' '#56b4e9');;

      'M' )
        et='mem'; eu='[GiB]';
        es=2.5; eh='';
        eas=('$3' '$4'); ens=('free' 'used'); ecs=('#e5bad2' '#cc79a7');;

    esac

    gnuimage="solo_${hourback}_${e}.png"
    pngs="${pngs} ${gnuimage}"

    cat << EOF > ${gnucmdtemplate}
reset
set terminal png transparent truecolor small size 480,120
set output '${gnuimage}'
set lmargin screen 0.092
set rmargin screen 0.972
set bmargin screen 0.130
set tmargin screen 0.970
set termoption enhanced
set grid
set style fill transparent solid 0.5
set xdata time
set timefmt '%Y-%m-%dT%H:%M'
set xrange['${xmin}':'${xmax}']
SET_YRANGE
set key top right reverse horizontal tc rgb "gray40"
set xtics format "${xtic}" offset 0,graph 0.03
set label '${eu}' at screen 0.01,0.5 rotate by 90 center
EOF

    case "${eu}" in
      *PiB*) ef=1099511627776;;
      *TiB*) ef=1073741824;;
      *GiB*) ef=1048576;;
      *MiB*) ef=1024;;
      *PB* ) ef=1000000000000;;
      *TB* ) ef=1000000000;;
      *GB* ) ef=1000000;;
      *MB* ) ef=1000;;
      *    ) ef=1;;
    esac

    for ie in ${!eas[@]}; do

      ea=${eas[${ie}]}
      en=${ens[${ie}]}
      ec=${ecs[${ie}]}

      gnudata="${gnudatapre}_${et}_${en}.txt"
      rm -f ${gnudata}

      for f in $(find ${e}_20??????.txt | sort | tac); do

        ymd8=$(echo ${f} | sed -e "s;${e}_;;" | sed -e 's;\.txt;;')

        [ ${ymd8} -lt ${ymdmin} ] && break
        [ ${ymd8} -gt ${ymdmax} ] && continue

        y4=$(echo ${ymd8} | cut -c1-4)
        m2=$(echo ${ymd8} | cut -c5-6)
        d2=$(echo ${ymd8} | cut -c7-8)

        ymdp0="${y4}-${m2}-${d2}"
        ymdp1="$(date -d "1 day ${ymdp0}" +'%Y-%m-%d')"

        tac ${f} \
          | awk '{if (($1 ~ /[0-9:]{8}/) && ($1 !~ /^00:00/ || NR > 5) && ($3 !~ /[A-Za-z]/)) print $1,'${ea}/${ef}';}' \
          | sed -e "s/^00:00/${ymdp1}T00:00/" \
          | sed -e "s/^\([0-9:]\{5\}\)/${ymdp0}T\1/" \
          >> ${gnudata}

      done # for f

      if [ ${ie} -eq 0 ]; then

        xlatest="$(head -n 1 ${gnudata} | cut -d' ' -f1 | cut -c01-16)"
        if [ $(date -d "${xmax}" +%s) -lt $(date -d "${xlatest}" +%s) ]; then
          xlatest=${xmax}
        fi

        cat << EOF >> ${gnucmdtemplate}
set label "${servername} ${et} ${backsuf}\n${xmin} to ${xlatest}" at graph 0.01,0.94 tc rgb "gray40"
EOF

      fi

      tac ${gnudata} > ${gnutemp}
      mv -f ${gnutemp} ${gnudata}

      gnuecho="'${gnudata}' using 1:2 \
        with filledcurves above y1=0 \
        title '${en}'"

      if [ ${ie} -eq 0 ]; then
        gnuecho="plot ${gnuecho} linecolor rgb '${ec}'"
      else
        gnuecho="     ${gnuecho} linecolor rgb '${ec}'"
      fi

      if [ ${#eas[@]} -ge 2 ] && [ ${ie} -lt $((${#eas[@]} - 1)) ]; then
        gnuecho="${gnuecho}, \\"
      fi

      echo ${gnuecho} >> ${gnucmdtemplate}

    done # for ie

    cat >> ${gnucmdtemplate} << EOF
set print "${gnuprint}"
print GPVAL_Y_MAX
EOF

    setyrange='set yrange[0:]'
    [ "${eh}" != '' ] && setyrange="set yrange[0:${eh}]"
    cat ${gnucmdtemplate} | sed -e "s/SET_YRANGE/${setyrange}/" > ${gnucmd}
    gnuplot ${gnucmd}

    if [ "${eh}" = '' ] && [ "${es}" != '' ]; then
      gpmax=$(head -n 1 ${gnuprint})
      if [ $(echo "1000 * (${gpmax} - ${es})" | bc | sed -e 's/\..*//') -lt 0 ]; then
        setyrange="set yrange[0:${es}]"
        cat ${gnucmdtemplate} | sed -e "s/SET_YRANGE/${setyrange}/" > ${gnucmd}
        gnuplot ${gnucmd}
      fi
    fi

    rm -f ${gnupre}*

  done # for e

  convert -append ${pngs} hour_${hourback}.png

done # for hourback

convert +append hour_*.png ${resultpath}

