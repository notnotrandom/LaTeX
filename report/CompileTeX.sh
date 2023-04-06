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
folders_to_be_rsyncd=( )

# If set to "false", suppresses the output of bibliography and index building
# commands. Set to any other value -- e.g. "true" -- to show said commands'
# output.
verbose="false"

# Name of the .bib file (sans extension).
sourcesname="sources"

# Build dir.
build_dir="build"

texcmd="xelatex"
texcmdopts="-halt-on-error --interaction=batchmode --shell-escape --synctex=1"
debug_texcmdopts="--interaction=errorstopmode --shell-escape --synctex=1 --output-directory=${build_dir}"
bibcmd="bibulous"
indexcmd="makeindex"

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
function big_build() {

  read -n1 -s -r -p $'Press <Enter> to continue (Ctrl-C to cancel)...' key
  if [ "$key" = '' ]; then
    echo
  else
    echo
    return 1
  fi

  local undef_refs=""

  echo "$0: Compile #1..."
  compile "$name" "$build_dir"

  # If the compile failed, notify the user and quit.
  if [[ $? -ne 0 ]]; then
    echo -e "Compilation of ${name}.tex file was ${ERROR}NOT SUCCESSFUL${NC}!"
    return 1
  fi

  # If the compile succeeded, then build the index (inside the regular build
  # dir).
  if [[ "$do_idx" == "true" ]] ; then
    if [[ "$verbose" == "false" ]]; then
      cd "${build_dir}"
      echo "$0: Index build..."
      ${indexcmd} ${name} > /dev/null
    else
      cd "${build_dir}" && pwd
      ${indexcmd} ${name}
    fi
  # If the building the index failed, notify the user and quit.
    if [[ $? -ne 0 ]]; then
      echo -e "Building of the index for ${name}.tex was ${ERROR}NOT SUCCESSFUL${NC}!"
      return 1
    fi
  # Otherwise leave the regular build dir.
    cd ..
  fi

  # If the previous compile succeeded, and we are not building bibliography,
  # then just compile twice more and exit.
  if [[ "$do_bib" == "false" ]] ; then
    echo "$0: The \$do_bib var is set to false, so I am skipping the bibliography part."
    echo "$0: I will just run compile() twice more."
    echo "$0: Compile #2 and #3..."
    compile "$name" "$build_dir" && compile "$name" "$build_dir"
  # If one of the compile runs failed, notify the user and quit.
    if [[ $? -ne 0 ]]; then
      echo -e "(2nd or 3rd) compile run of ${name}.tex file was ${ERROR}NOT SUCCESSFUL${NC}!"
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
      compile "$name" "$build_dir" && compile "$name" "$build_dir"
    # If one of the compile runs failed, notify the user and quit.
      if [[ $? -ne 0 ]]; then
        echo -e "(2nd or 3rd) compile run of ${name}.tex file was ${ERROR}NOT SUCCESSFUL${NC}!"
        return 1
      fi
    else
      # Some \cite or \nocite entries have been found -- hence build
      # bibliography and do two more compiles. And then check if there are
      # undef references.
      if [[ "$verbose" == "false" ]]; then
        cd "${build_dir}"
        echo "$0: Bibliography build #1..."
        ${bibcmd} "${name}.aux" > /dev/null
      else
        cd "${build_dir}" && pwd
        ${bibcmd} "${name}.aux"
      fi

      if [[ $? -eq 0 ]]; then
        cd ..
        echo "$0: Compile #2 and #3..."
        compile "$name" "$build_dir" && \
        compile "$name" "$build_dir"

        # Now check for undefined references.
        undef_refs=$(sed -En "s/^.+ Citation \`(.+)' on page .+ undefined.*$/\1/p" "${build_dir}/${name}.log")

        if [[ -n "$undef_refs" ]]; then
          # If undefined citations are found after the first two compiles after
          # having built the bibliography, then we need to re-build the
          # bibliography, and do two more compiles after that. But first warn
          # the user.
          echo "Found undefined citations: $undef_refs"
          echo "Re-building bibliography, and doing TWO more further compilations."

          if [[ "$verbose" == "false" ]]; then
            cd "${build_dir}"
            echo "$0: Bibliography build #2..."
            ${bibcmd} "${name}.aux" > /dev/null
          else
            cd "${build_dir}" && pwd
            ${bibcmd} "${name}.aux"
          fi
          if [[ $? -eq 0 ]]; then
            cd ..
            echo "$0: Compile #4 and #5..."
            compile "$name" "$build_dir" && \
            compile "$name" "$build_dir"
            if [[ $? -ne 0 ]]; then
              echo -e "Compile of ${name}.tex, after building bibliography (SECOND TIME), was ${ERROR}NOT SUCCESSFUL${NC}!"
              return 1
            fi
          else
            echo -e "Building bibliography (regular copy, SECOND TIME) file was ${ERROR}NOT SUCCESSful${NC}!"
            return 1
          fi
        fi

        # Whether or not there were undefined references, compile one final
        # time. In either case, this will be the third compile run after the
        # latest bibliography build.
        echo -n "$0: Compile (final run)... "
        compile "$name" "$build_dir"

        # If this last compile failed, notify the user and quit.
        if [[ $? -ne 0 ]]; then
          echo -e "Last compile of ${fname}.tex was ${ERROR}NOT SUCCESSFUL${NC}!"
          return 1
        fi
        echo -e "${SUCCESS}Success${NC}."

        # If the compiles were successful, but we still have undefined
        # references, then just warn the user, and let him deal with it.
        undef_refs=$(sed -En "s/^.+ Citation \`(.+)' on page .+ undefined.*$/\1/p" "${build_dir}/${name}.log")

        if [[ -n "$undef_refs" ]]; then
          echo "There are still undefined citations: $undef_refs!!"
        fi
      else
        echo -e "Building bibliography (first run) file was ${ERROR}NOT SUCCESSFUL${NC}!"
        return 1
      fi
    fi
  fi
}

function check_warnings() {
  grep 'LaTeX Warning' "build/${name}.log"
}

function clean() {
  if [[ -d "$build_dir" ]]; then
    echo "Wiping contents of ${build_dir} (except PDF files)"
    cd "${build_dir}" && rm -rf $(ls | grep -v ".pdf") && cd ..
  else
    echo "Creating directory ${build_dir}"
    mkdir $build_dir
  fi

  # Rebuilding structure of build_dirs. Begin with symlinks.
  symlinks_rebuild

  # And finish with build dir subfolders.
  update_build_dir_subfolders
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
  big_build "$name" "$build_dir"
  cp "${build_dir}"/"${name}.pdf" "${finalname}.pdf"
}

# Do a single compile run---and if it is successful, do the same for the
# unabridged copy.
function small_build() {
  echo -n "$0: Compiling... "
  compile "$name" "$build_dir" # compile() returns the $? of the LaTeX command. See Note (1).
  if [[ $? -ne 0 ]]; then
    echo -e "Compile of ${name}.tex file was ${ERROR}NOT SUCCESSFUL${NC}!"
    return 1
  else
    echo -e "${SUCCESS}Success${NC}."
  fi
}

function small_double_build() {
  echo -n "$0: Compiling... "
  compile "$name" "$build_dir" # compile() returns the $? of the LaTeX command. See Note (1).
  if [[ $? -ne 0 ]]; then
    echo -e "Compile of ${name}.tex file was ${ERROR}NOT SUCCESSFUL${NC}!"
    return 1
  else
    echo -e "${SUCCESS}Success${NC}."
  fi

  echo -n "$0: Compiling... "
  compile "$name" "$build_dir"
  if [[ $? -ne 0 ]]; then
    echo -e "Compile of ${name}.tex file was ${ERROR}NOT SUCCESSFUL${NC}!"
    return 1
  else
    echo -e "${SUCCESS}Success${NC}."
  fi
}

function symlinks_rebuild() {
  if [[ ! -d "$build_dir" ]]; then
    echo "Build dir does not exist! Run clean() to fix it."
    return 1
  fi

  rm -f "${name}.pdf"
  rm -f "${name}.synctex.gz"
  rm -f "${build_dir}/${sourcesname}.bib"

  ln -sr "${build_dir}/${name}.pdf" .
  ln -sr "${build_dir}/${name}.synctex.gz" .
  ln -sr ${sourcesname}.bib "${build_dir}"/
}

function update_build_dir_subfolders() {
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
    rsync -a --include '*/' --exclude '*' "${folders_to_be_rsyncd[@]%%+(/)}" "${build_dir}"
  fi
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
  elif [[ $# -eq 1 && "$1" == "double" ]] ; then
    small_double_build
  elif [[ $# -eq 1 && "$1" == "final" ]] ; then
    final_document
  elif [[ $# -eq 1 && "$1" == "subdirs" ]] ; then
    update_build_dir_subfolders
  elif [[ $# -eq 1 && "$1" == "symlinks" ]] ; then
    symlinks_rebuild
  elif [[ $# -eq 1 && "$1" == "warnings" ]] ; then
    check_warnings
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
