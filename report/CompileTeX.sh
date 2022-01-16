#! /bin/bash

# See the end of file for an overall explanation of this file.

# $name is one of: cv, bare, essay, llncs, presentation, report, or standalone.
name="report"

##### VARIABLES THAT THE USER CAN SET #####
# To disable building bibliography, set this to false.
do_bib="true"

# To enable building the index, set this to true.
do_idx="false"

# The final name of the .pdf file (without extension). Defaults to original
# name with ".FINAL" appended. In my setup, works "out of the box" with spaces,
# foreign chars, ...
finalname="${name}.FINAL"

# IMPORTANT: if you have .tex files in their own folders, indicate them here
# (space separated). E.g. if you have your chapters and frontmatter in folders
# named "chapters" and "frontmatter" (no quotes), then add them like this (WITH
# quotes):
# folders_to_be_rsyncd=( "chapters" "frontmatter" )
folders_to_be_rsyncd=()

# If set to "false", suppresses the output of bibliography and index building
# commands. Set to any other value -- e.g. "true" -- to show said commands'
# output.
verbose="false"

# IMPORTANT: set the temporary build dir here. Use a RAM-based temporary
# filesystem if you have one. See README.
tmp_build_dir="/run/user/$UID/xyz-temp-compile"
##### END VARIABLES THAT THE USER CAN SET #####

# Name of the .bib file (sans extension).
sourcesname="sources"

# Build dir for the regular (possibly abridged) copy.
build_dir_regular="build"

texcmd="xelatex"
texcmdopts="-halt-on-error --interaction=batchmode --shell-escape --synctex=1"
debug_texcmdopts="--interaction=errorstopmode --shell-escape --synctex=1 --output-directory=${build_dir_regular}"
bibcmd="bibulous"
indexcmd="makeindex"

# Data for unabridged copy.
name_unabridged="Unabridged"
build_dir_unabridged="build_UNABRIDGED"

# Colours.
SUCCESS='\033[0;34m'
ERROR='\033[0;31m'
NC='\033[0m' # No Color

# A big LaTeX compile: compile once (and build index, if it is set), then compile
# bib (if it is set), then compile two more times. After that, check the .log
# file to the see if there are undefined references. If this is so, that means
# there are \cite commands in the bibliographic references themselves. And so,
# we re-build the bibliography, and compile two more times. If everything is
# ok, compile once more, to ensure proper backrefs.
#
# If using bib is not set, or if it is set, but no \cite or \nocite commands
# are found, just compile three times.
#
# See also big_build().
function big_build_inner() {

  local fname="$1"
  local build_dir="$2"

  local undef_refs=""

  echo "$0: Compile #1..."
  compile "$fname" "$build_dir"
# If the compile failed, notify the user and quit.
  if [[ $? -ne 0 ]]; then
    echo -e "Compilation (ignoring \includeonly, if present) of ${fname}.tex file was ${ERROR}NOT SUCCESSFUL${NC}!"
    return 1
  fi

# If the compile succeeded, then build the index (inside the regular build dir).
  if [[ "$do_idx" == "true" ]] ; then
    if [[ "$verbose" == "false" ]]; then
      cd "${build_dir}"
      echo "$0: Index build..."
      ${indexcmd} ${fname} > /dev/null
    else
      cd "${build_dir}" && pwd
      ${indexcmd} ${fname}
    fi
# If the building the index failed, notify the user and quit.
    if [[ $? -ne 0 ]]; then
      echo -e "Building of the index for ${fname}.tex was ${ERROR}NOT SUCCESSFUL${NC}!"
      return 1
    fi
# Otherwise leave the regular build dir.
    cd ..
  fi

# If the previous compile succeeded, and we are not building bibliography, then
# just compile twice more and exit.
  if [[ "$do_bib" == "false" ]] ; then
    echo "$0: The \$do_bib var is set to false, so I am skipping the bibliography part."
    echo "$0: I will just run compile() twice more."
    echo "$0: Compile #2 and #3..."
    compile "$fname" "$build_dir" && compile "$fname" "$build_dir"
# If one of the compile runs failed, notify the user and quit.
    if [[ $? -ne 0 ]]; then
      echo -e "(2nd or 3rd) compile run of ${fname}.tex file was ${ERROR}NOT SUCCESSFUL${NC}!"
      return 1
    fi

# Else, if $do_bib is true, and there are uncommented \cite or \nocite
# commands, then build the bibliography. The reason for *three* compiles,
# instead of the usual two, is that an extra compile is required for
# backreferences in bib entries to be constructed (e.g. "Cited in page ...").
  else
    local have_cite_entries=$(grep --extended-regexp --recursive '^[^%]*\\(no)?cite' --include=*.tex)
# No \cite or \nocite entries have been found.
    if [[ -z "$have_cite_entries" ]]; then
      echo "$0: The $do_bib var is set to true, but no \\cite entries found.
      So I will just do two more compile runs..."
      echo "$0: Compile #2 and #3..."
      compile "$fname" "$build_dir" && compile "$fname" "$build_dir"
# If one of the compile runs failed, notify the user and quit.
      if [[ $? -ne 0 ]]; then
        echo -e "(2nd or 3rd) compile run of ${fname}.tex file was ${ERROR}NOT SUCCESSFUL${NC}!"
        return 1
      fi
# Some \cite or \nocite entries have been found -- hence build bibliography and
# do two more compiles. And then check if there are undef references.
    else
      if [[ "$verbose" == "false" ]]; then
        cd "${build_dir}"
        echo "$0: Bibliography build #1..."
        ${bibcmd} "${fname}.aux" > /dev/null
      else
        cd "${build_dir}" && pwd
        ${bibcmd} "${fname}.aux"
      fi

      if [[ $? -eq 0 ]]; then
        cd ..
        echo "$0: Compile #2 and #3..."
        compile "$fname" "$build_dir" && \
        compile "$fname" "$build_dir"

# Now check for undefined references.
        undef_refs=$(sed -En "s/^.+ Citation \`(.+)' on page .+ undefined.*$/\1/p" "${build_dir}/${fname}.log")

        if [[ -n "$undef_refs" ]]; then
# If undefined citations are found after the first two compiles after having
# built the bibliography, then we need to re-build the bibliography, and do two
# more compiles after that. But first warn the user.
          echo "Found undefined citations: $undef_refs"
          echo "Re-building bibliography, and doing TWO more further compilations."

          if [[ "$verbose" == "false" ]]; then
            cd "${build_dir}"
            echo "$0: Bibliography build #2..."
            ${bibcmd} "${fname}.aux" > /dev/null
          else
            cd "${build_dir}" && pwd
            ${bibcmd} "${fname}.aux"
          fi
          if [[ $? -eq 0 ]]; then
            cd ..
            echo "$0: Compile #4 and #5..."
            compile "$fname" "$build_dir" && \
            compile "$fname" "$build_dir"
            if [[ $? -ne 0 ]]; then
              echo -e "Compile of ${fname}.tex, after building bibliography (SECOND TIME), was ${ERROR}NOT SUCCESSFUL${NC}!"
              return 1
            fi
          else
            echo -e "Building bibliography (regular copy, SECOND TIME) file was ${ERROR}NOT SUCCESSful${NC}!"
            return 1
          fi
        fi
# Whether or not there were undefined references, compile one final time. In
# either case, this will be the third compile run after the latest bibliography
# build.
        echo -n "$0: Compile (final run)... "
        compile "$fname" "$build_dir"
# If this last compile failed, notify the user and quit.
        if [[ $? -ne 0 ]]; then
          echo -e "Last compile of ${fname}.tex was ${ERROR}NOT SUCCESSFUL${NC}!"
          return 1
        fi
        echo -e "${SUCCESS}Success${NC}."

# If the compiles were successful, but we still have undefined references, then
# just warn the user, and let him deal with it.
        undef_refs=$(sed -En "s/^.+ Citation \`(.+)' on page .+ undefined.*$/\1/p" "${build_dir}/${fname}.log")

        if [[ -n "$undef_refs" ]]; then
          echo "There are still undefined citations: $undef_refs!!"
        fi
      else
        echo -e "Building bibliography (first run, regular copy) file was ${ERROR}NOT SUCCESSFUL${NC}!"
        return 1
      fi
    fi
  fi
}

# Do a big build on the regular copy; and if it succeeds, do the same for the
# unabridged copy.
function big_build () {
# Big build for regular copy: if the main file has an \includeonly line, then we
# first create a temp copy of the whole dir, so as to remove that command (we
# can't do this on the main file itself, because it will likely be open for
# editing by the user). If the main file has no \includeonly line, then just do
# a big build (done in function big_build_inner()).
  if [[ "$(do_we_have_includeonly)" == "true" ]]; then
    big_compile_on_tmp_folder_comment_include_only

# We are using \includeonly, so after doing a big compile and getting the full
# (non-abridged) document, do an extra compile run to obtain the abridged
# version the user had before the big compile.
    compile "$name" "$build_dir_regular"
  else
    big_build_inner "$name" "$build_dir_regular"
  fi

# If big build of regular copy built correctly, then do big build for the
# unabridged one.
  echo -e "$0: Now continuing with unabridged (full) build..."

  if [[ $? -eq 0 ]]; then
    update_unabridged_tex_files
    big_build_inner "$name_unabridged" "$build_dir_unabridged"
  fi
}

# This function creates a copy of the main dir (excluding unabridged stuff),
# deletes the \includeonly line in $name.tex, and then does a big compile run.
# The reason is that there is little point in doing a big build with
# \includeonly, because things like citations or backrefs may come out wrong.
#
# After the big build, it replaces the main folder's build dir with this one,
# and deletes the copy folder.
function big_compile_on_tmp_folder_comment_include_only() {
  local curr_dir=$(pwd)

  rm -rf "$tmp_build_dir" && mkdir "$tmp_build_dir"

  cp -r $(ls | grep -v "docs\|$build_dir_unabridged\|$name_unabridged") "$tmp_build_dir"
  cd "$tmp_build_dir"

# Find ^\includeonly line in $name.tex, if any, and make it empty.
  sed -e 's/^\s*\\includeonly.*$//' -i "${name}.tex"

# We have to use our (tmp) copy of build_dir_regular, because the compiler will
# not use a build dir that is outside of the current dir.
  big_build_inner "$name" "./$build_dir_regular"
  local ret=$?

  cd "$curr_dir"
  rm -rf "${build_dir_regular}"
  mv "$tmp_build_dir"/"${build_dir_regular}" .

  rm -rf "$tmp_build_dir"
  return $ret
}

function clean() {
  if [[ -d "$build_dir_regular" ]]; then
    echo "Wiping contents of ${build_dir_regular} (except PDF files)"
    cd "${build_dir_regular}" && rm -rf $(ls | grep -v ".pdf") && cd ..
  else
    echo "Creating directory ${build_dir_regular}"
    mkdir $build_dir_regular
  fi

  if [[ -d "$build_dir_unabridged" ]]; then
    echo "Wiping contents of ${build_dir_unabridged} (except PDF files)"
    cd "${build_dir_unabridged}" && rm -rf $(ls | grep -v ".pdf") && cd ..
  else
    echo "Creating directory ${build_dir_unabridged}"
    mkdir $build_dir_unabridged
  fi

# Rebuilding structure of build_dirs. Begin with symlinks.
  unabridged_dir_and_symlinks_rebuild

# If any .tex files are in their own custom directories, those dirs
# must also exist in $build_dir, with the same hierarchy. See README.md for
# more details. Handled with rsync.

# In the rsync commands, the source arguments (folders) must not end with a
# forward slash. The %%+(/) appended to $folders_to_be_rsyncd strips such
# trailing slashes, if any. But in order for it to work, it requires the
# extglob option. The program shopt sets it with the -s option, and unsets it
# with -u.
  if [[ ${#folders_to_be_rsyncd[@]} -gt 0 ]] ; then
    shopt -s extglob
    rsync -a --include '*/' --exclude '*' "${folders_to_be_rsyncd[@]%%+(/)}" "${build_dir_regular}"

    rsync -a --include '*/' --exclude '*' "${folders_to_be_rsyncd[@]%%+(/)}" "${build_dir_unabridged}"
    shopt -u extglob
  fi
}

# A normal (single) LaTeX compile.
function compile() {
  ${texcmd} ${texcmdopts} --output-directory="$2" "$1" > /dev/null
  local ret=$?
  return $ret
}

# A normal (single) LaTeX compile.
function debugbuild() {
  ${texcmd} ${debug_texcmdopts} ${name}
  return $?
}

function do_we_have_includeonly() {
# This string is of nonzero length if $name.tex has an \includeonly line.
  local have_includeonly=$(grep --extended-regexp '^\s*\\includeonly' "${name}.tex")

  if [[ -n "$have_includeonly" ]]; then
    echo "true"
  else
    echo "false"
  fi
}

function final_document() {
  update_unabridged_tex_files
  big_build_inner "$name_unabridged" "$build_dir_unabridged"
  cp "${build_dir_unabridged}"/"${name_unabridged}.pdf" "${finalname}.pdf"
}

# Do a single compile run---and if it is successful, do the same for the
# unabridged copy.
function small_build() {
  echo -n "$0: Compiling... "
  compile "$name" "$build_dir_regular" # compile() returns the $? of the LaTeX command. See Note (1).
  if [[ $? -ne 0 ]]; then
    echo -e "Compile of ${name}.tex file was ${ERROR}NOT SUCCESSFUL${NC}!"
    return 1
  else
    echo -e "${SUCCESS}Success${NC}."
  fi

# If compile was successful, and we are using \includeonly, then update
# unabridged copy.
  if [[ "$(do_we_have_includeonly)" == "true" ]]; then
    update_unabridged_tex_files

    echo -n "$0: Compiling unabridged version... "

    compile "${name_unabridged}" "$build_dir_unabridged"
    if [[ $? -ne 0 ]]; then
      echo -e "Compile of ${name_unabridged}.tex file was ${ERROR}NOT SUCCESSFUL${NC}!"
      exit 1
    else
      echo -e "${SUCCESS}Success${NC}."
    fi
  else
# If \includeonly is not used, then unabridged version is just the normal
# version, so just copy the $name.pdf file to $name_unabridged.pdf.
    echo -e "$0: \includeonly not used, so unabridged copy == pdf file copy."

    cp "${build_dir_regular}/${name}.pdf" "${build_dir_unabridged}/${name_unabridged}.pdf"
    cp "${build_dir_regular}/${name}.synctex.gz" "${build_dir_unabridged}/${name_unabridged}.synctex.gz"
  fi
}

function u2r() {
  cp "$build_dir_unabridged/$name_unabridged".pdf "$build_dir_regular/$name".pdf
}

# Copy main .tex file as $name_unabridged, patch it to redefine all \include's
# as \input's. This causes for \includeonly to be ignored (if it exists). Then
# build unabridged copy in $build_dir_unabridged.
function update_unabridged_tex_files() {
  rm -f "${name_unabridged}.tex"

# Delete any \includeonly line from ${name_unabridged}.tex. This should not be
# necessary, as the sed below redefines \include to \input, which means that
# \includeonly lines will be ignored. But it is possible that there will exist
# other code that runs (or doesn't run) when an \includeonly line exists. So
# better wipe it out, just to be sure.
  sed -e 's/^\s*\\includeonly.*$//' "${name}.tex" > "${name_unabridged}.tex"

# Insert the following line before \begin{document}:
# \let\include\input
  sed '/^\s*\\begin{document}/i \
\\let\\include\\input' -i "${name_unabridged}.tex"
}

function unabridged_dir_and_symlinks_rebuild() {
  if [[ ! -d "$build_dir_regular" ]]; then
    echo "Build dir does not exist! Run clean() to fix it."
    return 1
  fi

# First deal with regular build dir.
  rm -f "${name}.pdf"
  rm -f "${name}.synctex.gz"
  rm -f "${build_dir_regular}/${sourcesname}.bib"

  ln -sr "${build_dir_regular}/${name}.pdf" .
  ln -sr "${build_dir_regular}/${name}.synctex.gz" .
  ln -sr ${sourcesname}.bib "${build_dir_regular}"/

# And then with unabridged build dir (only for reports).
  if [[ ! -d "$build_dir_unabridged" ]]; then
    echo "Unabridged build dir does not exist! Run clean() to fix it."
    return 1
  fi

  rm -f "${name_unabridged}.pdf"
  rm -f "${name_unabridged}.synctex.gz"
  rm -f "${build_dir_unabridged}/${sourcesname}.bib"

  ln -sr "${build_dir_unabridged}/${name_unabridged}.pdf" .
  ln -sr "${build_dir_unabridged}/${name_unabridged}.synctex.gz" .
  ln -sr ${sourcesname}.bib "${build_dir_unabridged}"/
}

#
# *** Main function ***
#
function main() {
# Check that we are in the dir containing the main file.
  if ! [[ -f "${name}.tex" ]]; then
    echo "Could not find main file ${name}.tex. Exiting..."
    exit 1
  fi

# If no arguments given, do a normal build;
# - argument is debug: do debug build;
  if [[ $# -eq 0 ]] ; then
    small_build
  elif [[ $# -eq 1 && "$1" == "big" ]] ; then
    big_build
  elif [[ $# -eq 1 && "$1" == "clean" ]] ; then
    clean
  elif [[ $# -eq 1 && "$1" == "debug" ]] ; then
    debugbuild
  elif [[ $# -eq 1 && "$1" == "final" ]] ; then
    final_document
  elif [[ $# -eq 1 && "$1" == "symlinks" ]] ; then
    unabridged_dir_and_symlinks_rebuild
  elif [[ $# -eq 1 && "$1" == "u2r" ]] ; then
    u2r
  else
    echo "Unknown option(s): $@"
    exit 1
  fi
}

main "$@"

################################################################################
#
# Much like targets in a Makefile, this scripts provides functions to do a
# simple build, a full build, etc, for a LaTeX project.
#
# Three main functions, compile(), small_build(), and big_build():
#
# - compile() just runs the LaTeX compiler on whatever file it is given.
#
# - small_build() runs compile() on the regular copy, and then (if using
# \includeonly) on the unabridged copy. If \includeonly is not used, after
# compiling the regular copy, it just copies the pdf file---because in this
# case, both regular and unabridged versions match.
#
# - big_build() is the function supposed to be run when updating bibliographic
# references, indexes, etc. It is tricky to run when also using \includeonly;
# so it actually builds the entire document. See the comments therein for
# further information.
#
# Most of the remaining functions revolve around these three, to compile both
# the report and its unabridged version, and to check for errors and give
# feedback properly, and so on.
#
################################################################################

###

# Notes:
# - (1) After an unsuccessful compilation, and after fixing the mistake that
#   caused it, a normal compile, in batchmode with halt on errors, will still lead
#   to a natbib error. It goes away after doing another normal compile. But perhaps
#   the best strategy is to do debug mode in case of errors...
