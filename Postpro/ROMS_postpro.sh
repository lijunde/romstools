#!/bin/bash
#
if [ $# -ne 1 ]; then
  echo
  echo 'Usage: ROMS_postpro.sh <def-file>'
  echo
  echo ' def-file: Ascii-file with definitions set in execute_postpro.sh'
  exit
fi
#
# Read definitions and switches from a temporary definition-file made by execute_postpro.sh
#
module swap PrgEnv-pgi PrgEnv-gnu
module unload notur

inpfil=${1}
read out_zeta out_fluxes out_curr out_curr_rot out_curr_polar out_salt out_temp \
     out_slevel                                                                 \
     exp                                                                        \
     x0 x1 y0 y1                                                                \
     nsplitarea                                                                 \
     RDIR machine                                                               \
     roms2z roms2s filestat_z filestat_s                                        \
     out_zlevels                                                                < ${inpfil}
rm ${inpfil}
#
# Set origin path
#
BASE=`pwd`
cd ${BASE}
#
# Make sure nco-module is loaded
module load nco
#
if [ ${roms2z} -eq 1 ]; then  # Interpolate ROMS results from s-levels/C-grid to z-levels/A-grid
#
# Find files to read
  modfiles=`ls ${RDIR}/*`
  if [ -s ${BASE}/filelist.asc ]; then rm ${BASE}/filelist.asc; fi
  for modfile in ${modfiles}; do
    echo ${modfile} >> ${BASE}/filelist.asc
  done

  echo
  echo "The following ROMS output files from ${RDIR} will be read:"
  cat ${BASE}/filelist.asc
  echo
#
  if [ ${out_zeta}       -eq 1 ]; then echo "Sea level will be written to file with the other 3D z-level fields"; fi
  if [ ${out_fluxes}     -eq 1 ]; then echo "Surface net heat and salt fluxes will be written to file with the other 3D z-level fields"; fi
  if [ ${out_curr}       -eq 1 ]; then echo "Ocean currents (x,y) will be written to file on z-levels"; fi
  if [ ${out_curr_rot}   -eq 1 ]; then echo "Ocean currents (eastward,northward) will be written to file on z-levels"; fi
  if [ ${out_curr_polar} -eq 1 ]; then echo "Ocean currents (angle,speed) will be written to file on z-levels"; fi
  if [ ${out_salt}       -eq 1 ]; then echo "Salinities will be written to file on z-levels"; fi
  if [ ${out_temp}       -eq 1 ]; then echo "Temperatures will be written to file on z-levels"; fi
#
  k=0
  for z in ${out_zlevels}; do
    if [ ${z} -lt 0 ]; then echo "Error, use positive depths only: ${z}"; exit; fi
    k=`expr ${k} + 1`
  done
  echo "The following ${k} z-levels are defined as output depths: ${out_zlevels}"
#
# Interpolate to A-grid and z-levels
#
  cd ${BASE}
  if [ -s roms2z ]; then rm roms2z *.o; fi
  if [ ${machine} == 'hexagon' ]; then
    module unload xtpe-interlagos       # Makes it possible to run programs on login-nodes
  fi
  make -f Makefile_roms2z_${machine}
  if [ ${machine} == 'hexagon' ]; then
    module load xtpe-interlagos
  fi
#
  if [ -s roms2z ]; then   # Run program
    ./roms2z << EOF
${BASE}/filelist.asc
${out_zeta} ${out_fluxes} ${out_curr} ${out_curr_rot} ${out_curr_polar} ${out_salt} ${out_temp}
${BASE}/${exp}_z.nc
${k}
${out_zlevels}

! Standard input to roms2z:
! Line 1) Name of ascii file containing a list of model result files that is read (full path for one file per line)
! Line 2) Define output fields (0=no,1=yes) in this order: zeta, fluxes(T+S), vel(u+v), vel(east,north), vel(polar coord.), salt, temp
! Line 3) Output file with depth dependent fields in z-levels + zeta/fluxes (if zeta/fluxes=1 in line 4)
! Line 4) No. of output vertical z-levels
! Line 5) Specify the z-levels (positive numbers, may be float)
EOF
  else
    echo 'Program Postpro/roms2z/roms2z did not compile properly!'
    exit
  fi
#
  cd ${BASE}
  rm ${BASE}/filelist.asc
  echo "New file with model fields on z-levels located as " `${BASE}/${exp}_z.nc`
#
fi  # [ ${roms2z} -eq 1 ]
#
if [ ${roms2s} -eq 1 ]; then  # Extract ROMS results from a pre-defined s-level
#
# Find files to read
  modfiles=`ls ${RDIR}/*`
  echo
  echo "The following ROMS output files from ${RDIR} will be read:"
  echo ${modfiles}
  echo
#
  if [ ${out_slevel} -lt 1 ]; then echo "Error, s-levels must be denoted as a positive integer: ${out_slevel}"; exit; fi
#
# List variables to include in output file
  vars="angle,theta_s,theta_b,Tcline,h,mask_rho,mask_u,mask_v,lon_rho,lat_rho,lon_u,lat_u"  # Constant parameters/fields
  if [ ${out_zeta}       -eq 1 ]; then vars="${vars},zeta"; fi
  if [ ${out_curr}       -eq 1 ]; then vars="${vars},u,v"; fi
  if [ ${out_curr_polar} -eq 1 ] && [ ${out_curr} -ne 1 ]; then echo "Cannot print water_spd and water_dir without u and v!"; exit; fi
  if [ ${out_salt}       -eq 1 ]; then vars="${vars},salt"; fi
  if [ ${out_temp}       -eq 1 ]; then vars="${vars},temp"; fi
  #vars=`echo ${vars} | sed 's/,//'`  # Remove the first comma
#
  echo
  echo "The following s-level will be extracted from model files: ${out_slevel}"
  i=0
  for modfile in ${modfiles}; do
    i=`expr ${i} + 1`
    ii=${i}
    if [ ${i} -lt 100 ]; then ii=0${i}; fi
    if [ ${i} -lt 10 ]; then ii=00${i}; fi
    ncea -O -F -v ${vars} -d s_rho,${out_slevel},${out_slevel} ${modfile} ${BASE}/${exp}_s_${ii}.nc
    echo "Extracted s-level fields from ${modfile} and written to ${BASE}/${exp}_s_${ii}.nc"
  done
  ncrcat -O ${BASE}/${exp}_s_???.nc ${BASE}/${exp}_s_Cgrid.nc
  rm ${BASE}/${exp}_s_???OB
#
# Interpolate fields on s-level from C-grid to A-grid
#
#  cd ${BASE}/roms2z
  if [ -s roms2agrid ]; then rm roms2agrid *.o; fi
  if [ ${machine} == 'hexagon' ]; then
    module unload xtpe-interlagos       # Makes it possible to run programs on login-nodes
  fi
  make -f Makefile_roms2agrid_${machine}
  if [ ${machine} == 'hexagon' ]; then
    module load xtpe-interlagos
  fi
#
  if [ -s roms2agrid ]; then   # Run program
    ./roms2agrid << EOF
${BASE}/${exp}_s_Cgrid.nc
${out_zeta} ${out_curr} ${out_curr_polar} ${out_salt} ${out_temp}
${BASE}/${exp}_s.nc

! Standard input to roms2agrid:
! Line 1) Name of input file containing fields on s-level(s) on original ROMS C-grid
! Line 2) Define output fields (0=no,1=yes) in this order: zeta, vel(u+v), vel(polar coord.), salt, temp
! Line 3) Output file with fields on A-grid
EOF
  else
    echo 'Program Postpro/roms2agrid/roms2agrid did not compile properly!'
    exit
  fi
#
  echo "New file with model fields on (fewer) s-levels and on A-grid located as " `ls ${BASE}/${exp}_s.nc`
  echo
#
fi  # [ ${roms2s} -eq 1 ]
#
if [ ${filestat_z} -eq 1 ]; then  # Create files with statistics
#
# Test that input file with model results on z-levels exists
  if [ -s ${BASE}/${exp}_z.nc ]; then
#
# Test that defined hyperslab is within actual grid size
    modfiles=`ls ${RDIR}/*`
    for modfile in ${modfiles}; do
      echo ${modfile} >> ${BASE}/filelist.asc
    done
    read ifil < ${BASE}/filelist.asc
    rm ${BASE}/filelist.asc
    ncdump -h ${ifil} > tmp.txt
    while read a b c d; do if [ ! -z ${a} ]; then if [ ${a} == "xi_rho" ];  then xi_rho=${c};  fi; fi; done < tmp.txt
    while read a b c d; do if [ ! -z ${a} ]; then if [ ${a} == "eta_rho" ]; then eta_rho=${c}; fi; fi; done < tmp.txt
    L=`expr ${xi_rho} - 2`; M=`expr ${eta_rho} - 2`;
    rm tmp.txt
    if [ ${x0} -lt 1 ] || [ ${x1} -gt ${L} ] || [ ${y0} -lt 1 ] || [ ${y1} -gt ${M} ]; then
      echo "Your definition of subarea is not valid. Grid dimension (interior rho-points) is ${L} x ${M}."
      echo "You have defined subarea as (x0-x1): ${x0} - ${x1} and (y0-y1): ${y0} - ${y1}."
      exit
    fi
#
    echo "Calculate statistics from file with model results on A-grid/z-levels:"
#   Get hyperslab based on defined subdomain
    ncks -a -O -F -d x,${x0},${x1} -d y,${y0},${y1} ${BASE}/${exp}_z.nc ${BASE}/${exp}_z_sub.nc
    echo "Hyperslab is made from file with model fields on z-levels, limits used are x:${x0}-${x1} and y:${y0}-${y1}"
    echo "New output file is " `ls ${BASE}/${exp}_z_sub.nc`
#
#   Calculate time average for all fields (possible to limit number of fields according to min/max time steps and/or stride
    ncra -O -F -d time,1,,1 ${BASE}/${exp}_z_sub.nc ${BASE}/${exp}_z_sub_mean.nc
    echo "Time averaged fields calculated and stored on " `ls ${BASE}/${exp}_z_sub_mean.nc`
#   Find rms values over dimension time
    ncra -O -y rms ${BASE}/${exp}_z_sub.nc ${BASE}/${exp}_z_sub_rms.nc
    echo "Fields with root mean squared values found and stored on " `ls ${BASE}/${exp}_z_sub_rms.nc`
#
#   Split the last tasks according to memory limitations
    xpnts=`expr ${x1} - ${x0} + 1`; ypnts=`expr ${y1} - ${y0} + 1`;
    if [ ${xpnts} -ge ${ypnts} ]; then
      dim='x';
      size=`expr ${xpnts} \/ ${nsplitarea}`;
      echo "x-dim > y-dim, split area in x-direction, xpnts=${xpnts}, xpnts/areas=${xpnts}/${nsplitarea}=${size}"
    else
      dim='y';
      size=`expr ${ypnts} \/ ${nsplitarea}`;
      echo "y-dim > x-dim, split area in y-direction, ypnts=${ypnts}, ypnts/areas=${ypnts}/${nsplitarea}=${size}"
    fi
#
    for (( n=1; n<=${nsplitarea}; n++)); do  # Loop over no. of tiles that min, max and std fields must be split
      a=`expr ${n} - 1`; a=`expr ${a} \* ${size} + 1`
      b=`expr ${n} \* ${size}`; btxt=${b};
      if [ ${n} -eq ${nsplitarea} ]; then b=; btxt='end'; fi  # Last tile must reach end of full grid
      echo "Area no. ${n} covers ${dim}-gridpoints from ${a} to ${btxt}"
#
#     Find minimum values over dimension time
      ncwa -O -F -d ${dim},${a},${b},1 -y min -a time ${BASE}/${exp}_z_sub.nc ${BASE}/${exp}_z_sub_min_${n}.nc
      echo "Fields with minimum values for area ${n} found and stored on " `ls ${BASE}/${exp}_z_sub_min_${n}.nc`
#     Find maximum values over dimension time
      ncwa -O -F -d ${dim},${a},${b},1 -y max -a time ${BASE}/${exp}_z_sub.nc ${BASE}/${exp}_z_sub_max_${n}.nc
      echo "Fields with maximum values for area ${n} found and stored on " `ls ${BASE}/${exp}_z_sub_max_${n}.nc`
#   Find standard deviation values over dimension time
      ncwa -O -F -d ${dim},${a},${b},1 -a time ${BASE}/${exp}_z_sub.nc ${BASE}/${exp}_z_sub_std_${n}.nc
      ncbo -O -F -d ${dim},${a},${b},1 --op_typ=sub ${BASE}/${exp}_z_sub.nc ${BASE}/${exp}_z_sub_std_${n}.nc ${BASE}/${exp}_z_sub_std_${n}.nc
      ncra -O -y rmssdn ${BASE}/${exp}_z_sub_std_${n}.nc ${BASE}/${exp}_z_sub_std_${n}.nc
      echo "Fields with standard deviation values for area ${n} found and stored on " `ls ${BASE}/${exp}_z_sub_std_${n}.nc`
    done  # n
#
  fi  # [ -s ${BASE}/${exp}_z.nc ]
#
fi  # [ ${filestat_z} -eq 1 ]
#
if [ ${filestat_s} -eq 1 ]; then  # Create files with statistics
#
# Test that input file with model results on s-level exists
  if [ -s ${BASE}/${exp}_s.nc ]; then
#
# Test that defined hyperslab is within actual grid size
    modfiles=`ls ${RDIR}/*`
    for modfile in ${modfiles}; do
      echo ${modfile} >> ${BASE}/filelist.asc
    done
    read ifil < ${BASE}/filelist.asc
    rm ${BASE}/filelist.asc
    ncdump -h ${ifil} > tmp.txt
    while read a b c d; do if [ ! -z ${a} ]; then if [ ${a} == "xi_rho" ];  then xi_rho=${c};  fi; fi; done < tmp.txt
    while read a b c d; do if [ ! -z ${a} ]; then if [ ${a} == "eta_rho" ]; then eta_rho=${c}; fi; fi; done < tmp.txt
    L=`expr ${xi_rho} - 2`; M=`expr ${eta_rho} - 2`;
    rm tmp.txt
    if [ ${x0} -lt 1 ] || [ ${x1} -gt ${L} ] || [ ${y0} -lt 1 ] || [ ${y1} -gt ${M} ]; then
      echo "Your definition of subarea is not valid. Grid dimension (interior rho-points) is ${L} x ${M}."
      echo "You have defined subarea as (x0-x1): ${x0} - ${x1} and (y0-y1): ${y0} - ${y1}."
      exit
    fi
#
    echo "Calculate statistics from file with model results on C-grid/s-level:"
#   Get hyperslab based on defined subdomain
    ncks -a -O -F -d x,${x0},${x1} -d y,${y0},${y1} ${BASE}/${exp}_s.nc ${BASE}/${exp}_s_sub.nc
    echo "Hyperslab is made from file with model fields on z-levels, limits used are x:${x0}-${x1} and y:${y0}-${y1}"
    echo "New output file is " `ls ${BASE}/${exp}_s_sub.nc`
#
#   Calculate time average for all fields (possible to limit number of fields according to min/max time steps and/or stride
    ncra -O -F -d time,1,,1 ${BASE}/${exp}_s_sub.nc ${BASE}/${exp}_s_sub_mean.nc
    echo "Time averaged fields calculated and stored on " `ls ${BASE}/${exp}_s_sub_mean.nc`
#   Find rms values over dimension time
    ncra -O -y rms ${BASE}/${exp}_s_sub.nc ${BASE}/${exp}_s_sub_rms.nc
    echo "Fields with root mean squared values found and stored on " `ls ${BASE}/${exp}_s_sub_rms.nc`
#
#   Split the last tasks according to memory limitations
    xpnts=`expr ${x1} - ${x0} + 1`; ypnts=`expr ${y1} - ${y0} + 1`;
    if [ ${xpnts} -ge ${ypnts} ]; then
      dim='x';
      size=`expr ${xpnts} \/ ${nsplitarea}`;
      echo "x-dim > y-dim, split area in x-direction, xpnts=${xpnts}, xpnts/areas=${xpnts}/${nsplitarea}=${size}"
    else
      dim='y';
      size=`expr ${ypnts} \/ ${nsplitarea}`;
      echo "y-dim > x-dim, split area in y-direction, ypnts=${ypnts}, ypnts/areas=${ypnts}/${nsplitarea}=${size}"
    fi
#
    for (( n=1; n<=${nsplitarea}; n++)); do  # Loop over no. of tiles that min, max and std fields must be split
      a=`expr ${n} - 1`; a=`expr ${a} \* ${size} + 1`
      b=`expr ${n} \* ${size}`; btxt=${b};
      if [ ${n} -eq ${nsplitarea} ]; then b=; btxt='end'; fi  # Last tile must reach end of full grid
      echo "Area no. ${n} covers ${dim}-gridpoints from ${a} to ${btxt}"
#
#     Find minimum values over dimension time
      ncwa -O -F -d ${dim},${a},${b},1 -y min -a time ${BASE}/${exp}_s_sub.nc ${BASE}/${exp}_s_sub_min_${n}.nc
      echo "Fields with minimum values for area ${n} found and stored on " `ls ${BASE}/${exp}_s_sub_min_${n}.nc`
#     Find maximum values over dimension time
      ncwa -O -F -d ${dim},${a},${b},1 -y max -a time ${BASE}/${exp}_s_sub.nc ${BASE}/${exp}_s_sub_max_${n}.nc
      echo "Fields with maximum values for area ${n} found and stored on " `ls ${BASE}/${exp}_s_sub_max_${n}.nc`
#     Find standard deviation values over dimension time
      ncwa -O -F -d ${dim},${a},${b},1 -a time ${BASE}/${exp}_s_sub.nc ${BASE}/${exp}_s_sub_std_${n}.nc
      ncbo -O -F -d ${dim},${a},${b},1 --op_typ=sub ${BASE}/${exp}_s_sub.nc ${BASE}/${exp}_s_sub_std_${n}.nc ${BASE}/${exp}_s_sub_std_${n}.nc
      ncra -O -y rmssdn ${BASE}/${exp}_s_sub_std_${n}.nc ${BASE}/${exp}_s_sub_std_${n}.nc
      echo "Fields with standard deviation values for area ${n} found and stored on " `ls ${BASE}/${exp}_s_sub_std_${n}.nc`
    done  # n
#
  fi  # [ -s ${${BASE}/${exp}_s.nc} ]
#
fi  # [ ${filestat_s} -eq 1 ]
#
exit
#

