(** Global -- global variables (minimal), debugging, and utility functions.
    AVOID MODULE-SPECIFIC ADDITIONS to this file; stick with utilities and
    *truly* global variables.  Many of these utilities are
    self-explanatory/short, thus minimal commenting. *)
open Str
open Printf
open Hashtbl
open List
open Unix
open Pervasives

let gui = ref false

(* we copy all debugging output to a file and to stdout *)
let debug_out = ref stdout 
let debug ?force_gui:(force_gui=false) fmt = 
  let k result = begin
    if force_gui || not !gui then begin
      output_string !debug_out result ; 
      output_string stdout result ; 
      flush stdout ; 
      flush !debug_out;
    end
  end in
    Printf.kprintf k fmt 

let abort fmt = 
  let k result = begin
    if not !gui then begin
      output_string !debug_out result ; 
      output_string stdout result ; 
      flush stdout ; 
      flush !debug_out;
    end;
    exit 1 
  end in
    debug "\nABORT:\n\n" ; 
    Printf.kprintf k fmt 

(* return a copy of 'lst' where each element occurs once *)
let uniq lst = 
  let ht = Hashtbl.create 255 in 
  let lst = List.filter (fun elt ->
    if Hashtbl.mem ht elt then false
    else begin
      Hashtbl.add ht elt () ;
      true 
    end 
  ) lst in
    lst 

let float_array_to_str fa =
  let b = Buffer.create 255 in
  let size = Array.length fa in 
    Array.iteri (fun i v -> 
      Printf.bprintf b "%g" v ;
      if i < pred size then Printf.bprintf b ", " 
    ) fa ;
    Buffer.contents b 

(* split "filename.dat" into ["filename";"dat"] *) 
let split_ext name =
  try 
    let base = Filename.chop_extension name in
    let ext = String.sub name ((String.length base)+1)
      ((String.length name) - ((String.length base)+1))
    in 
      base,ext
  with _ -> name,""

(* split "./src/filename.dat" into ["directories/directories",
   "filename";"data"] *)
let split_base_subdirs_ext name =
  try 
    let base = Filename.basename name in
    let basename,ext = split_ext base in
      Filename.dirname name,basename,ext
  with _ -> "",name,""

let pair_compare (a,_) (b,_) = compare a b

(* Returns the elements of 'lst' in a random order. *) 
let random_order lst = 
  let a = List.map (fun x -> (Random.float 1.0), x) lst in
  let b = List.sort pair_compare a in
    List.map (fun (_,a) -> a) b 


(* given "a/b/c.txt", create "a/" and then "a/b/" if they don't already exist *)
let rec ensure_directories_exist filename = 
  match split_base_subdirs_ext filename with
  | "",_,_ | ".",_,_ | "/",_,_ -> () 
  | dirname,_,_ -> 
    ensure_directories_exist dirname ; 
    (try Unix.mkdir dirname 0o755 with _ -> ())

let file_size name = (* return the size of the given file on the disk *) 
  try 
    let stats = Unix.stat name in
      stats.Unix.st_size 
  with _ -> 0 

(* This makes a deep copy of an arbitrary Ocaml data structure *) 
let copy (x : 'a) = 
  let str = Marshal.to_string x [] in
    (Marshal.from_string str 0 : 'a) 
(* Cil.copyFunction does not preserve stmt ids! Don't use it! *) 

let copy_closures (x : 'a) = 
  let str = Marshal.to_string x [Marshal.Closures] in
    (Marshal.from_string str 0 : 'a) 

(* a weighted coin toss with probability p *) 
let probability p = 
  if p <= 0.0 then false
  else if p >= 1.0 then true
  else Random.float 1.0 <= p 

(* read an integer from a string with error reporting *) 
let my_int_of_string str =
  try 
    let res = ref 0 in 
      Scanf.sscanf str " %i" (fun i -> res := i) ;
      !res
  with _ -> begin 
    if String.lowercase str = "true" then 1
    else if String.lowercase str = "false" then 0 
    else failwith ("cannot convert to an integer: " ^ str)
  end 

let my_float_of_string str =
  try 
    let res = ref 0.0 in 
      Scanf.sscanf str " %f" (fun i -> res := i) ;
      !res
  with _ -> begin 
    if String.lowercase str = "true" then 1.0
    else if String.lowercase str = "false" then 0.0
    else failwith ("cannot convert to a float: " ^ str)
  end 

let file_to_string (file : string) : string = 
  let b = Buffer.create 255 in 
    try 
      let fin = open_in file in 
        (try while true do
            let line = input_line fin in
              Buffer.add_string b line ; 
              Buffer.add_char b '\n' ; 
          done ; with _ -> begin close_in fin end) ;
        Buffer.contents b 
    with _ -> Buffer.contents b 

(* Counts the number of lines in a simple text file.
 * Returns the integer number as a float. *) 
let count_lines_in_file (file : string) 
                        (* returns: *) : float =
  try 
    let fin = open_in file in 
    let count = ref 0 in
      (try while true do
          let line = input_line fin in
            ignore line ;
            incr count 
        done ; 0. with _ -> begin close_in fin ; float_of_int !count end) 
  with _ -> 0.

(* This makes multi-line docs wrap prettily *)
(* FIXME: this doesn't work for some reason *)
let my_align options = 
  try
    let len = String.length in
    let sub = String.sub in 
    let make_space num = String.make num ' ' in
    let max = List.fold_left ( fun prev (a, b, c) ->
      if (len a) > prev then len a else prev ) 0 options in

    let re = Str.regexp "[ ]" in
      List.map ( fun (a, b, c)  ->
        let a, c = 
          if c.[0] == 'X' then
            a ^ " X", (sub c 2 ((len c) - 2))
          else if c.[0] == ' ' then
            a, (sub c 1 ((len c) - 1))
          else
            a, c 
        in
          
        let wordlist = Str.split re c in

        let space = make_space (max - (len a) + 4)  in
        let c = space ^ c in

        let length = (len a) + (len c) in
          
                             (* the allowable width minus leading blank *)
        let width = 80 - ((len a + 3) + (len space)) in
        let c = 
          if length >= 78 then begin
            let lines = ref [] in
            let testline = ref "" in  
            let current = ref "" in
              
              (* Make linebreaks if the next word will push us over 80 chars*)
              List.iter ( fun s -> 
                begin
                  current := (!testline ^ " " ^  s) ;
                  if (len !current) > width then
                    begin
                      lines := !testline::!lines ;
                      testline := s 
                    end
                  else
                    testline := !current
                end) wordlist ;
              
              (* add on the final line *)
              lines := !testline::!lines;
              lines := List.rev !lines;
              let firstspace = make_space (len space  - 1) in
              let first_line = firstspace ^ (List.hd !lines) ^ "\n" in
                
              let subsequent_space = make_space ((len a) + (len space) + 3) in
              let rest = List.tl !lines in
                
              let result = List.fold_left (fun sofar next ->
                sofar ^ subsequent_space ^  next ^ "\n"
              ) first_line rest 
              in
                sub result 0 ((len result) - 1)
          end
          else c in (a, b, c)
      ) options
  with _ ->  Arg.align options 


let get_lines (filename : string) : string list = 
  let fin = open_in filename in
  let res = ref [] in
    (try
       while true do
         res := (input_line fin) :: !res
       done
     with End_of_file -> close_in fin);
    List.rev !res

let iter_lines filename func = 
  let fin = open_in filename in
  let rec dolines () =
    try
      let line = input_line fin in 
        func line; dolines()
    with End_of_file -> close_in fin
  in
    dolines ()

(* returns the first N elements of the given list *) 
let rec first_nth lst n =  
  if n < 1 then [] 
  else match lst with
  | [] -> []
  | hd :: tl -> hd :: (first_nth tl (pred n))

(* return the first N elements of a list and the remainder as well *)
let rec split_nth lst n =  
  if n < 1 then [], lst 
  else match lst with
  | [] -> [], [] 
  | hd :: tl -> 
    let first_part, last_part = split_nth tl (pred n) in
      hd :: first_part, last_part

let random_seed = ref 0 
let program_to_repair = ref "" 
let pos_tests = ref 5 
let neg_tests = ref 1 
let extension = ref "" 
let search_strategy = ref "brute"
let incoming_pop_file = ref "" 

let usageMsg = "Program Repair Prototype (v2)\n" 
let options = ref [
  "--program", Arg.Set_string program_to_repair, "X repair X";

  "--seed", Arg.Set_int random_seed, "X use X as random seed";

  "--pos-tests", Arg.Set_int pos_tests, "X number of positive tests";

  "--neg-tests", Arg.Set_int neg_tests, "X number of negative tests";

  "--search", Arg.Set_string search_strategy, 
  "X use strategy X (brute, ga, neutral, oracle, walk)";

  "--gui", Arg.Set gui, " enable phone GUI demo-based output. gui";

] 

let space_regexp = Str.regexp "[ \t]+" 
let whitespace_regexp = space_regexp 
let comma_regexp = regexp_string ","


let deprecated_options = [
  "--recompute-weights"; "--neutral"; "--mutrb-runs"; "--neutral-walk-steps";
  "--oracle-search-string";
  "--use-subdirs"; "--use-full-paths"; "--multi-file"; "--skip-sanity";
  "--force-sanity"; "--use-subatoms"; "--print-func-lines";
  "--print-line-numbers"; "--print-fix-info"; "--one-pos";
  "--neutral-walk-pop-size"; "--suffix-extension"; "--no-canonify-sids";
  "--server"; "--delete-subdirs"; "--coverage-out"; "--output-binrep";
  "--apply-diff"; "--debug-put";  "--uniq-cov";
  "--robustness-ops"; "--preprocess"; "--preprocessor";
  "--asm-sample-runs"; "--elf-sample-runs"; "--use-line-file";
  "--use-path-file"; "--allow-sanity-fail"; "--prepare"; "--mutp"
]

let deprecated_and_not_ok = [
  "--print-func-lines";
  "--neutral";
  "--print-line-numbers"; "--one-pos";
  "--no-canonify-sids";
  "--server"; "--coverage-out"; "--output-binrep";
  "--apply-diff"; "--debug-put"; 
  "--convert-swaps";
  "--preprocess"; "--preprocessor";
  "--use-line-file"; "--mutp";
  "--use-path-file";
]

(* FIXME: apply-diff to deprecated_and_simulable *)
let with_arg = [
  "--neutral"; "--mutrb-runs";"--neutral-walk-steps"; "--neutral-walk-pop-size";
  "--suffix-extension";"--coverage-out";"--apply-diff";"--robustness-ops";
  "--asm-sample-runs";"--elf-sample-runs";"--oracle-search-string"
]

let deprecated_but_ok = [
  "--recompute-weights";
  "--use-subdirs"; "--use-full-paths"; "--multi-file"; "--print-fix-info"; 
 "--suffix-extension"; "--delete-subdirs";  "--use-subatoms";
(* I'm assuming that if you say use-subatoms you also set subatom_mutp to something *)
]

let new_deprecated_args = ref "" 

let deprecated_and_simulable = [
  "--oracle-search-string", Arg.String (fun arg ->
    let str = Printf.sprintf "--oracle-genome %s " arg in
      new_deprecated_args := !new_deprecated_args^str), "";

  "--mutrb-runs", 
  Arg.Int (fun runs -> 
    let str = Printf.sprintf "--generations %d " runs in
      new_deprecated_args := !new_deprecated_args^str), "";

  "--neutral-walk-steps",
  Arg.Int (fun runs -> 
    let str = Printf.sprintf "--generations %d " runs in
      new_deprecated_args := !new_deprecated_args^str), "";

  "--skip-sanity",
  Arg.Unit (fun () -> 
    let str = Printf.sprintf "--sanity no " in
      new_deprecated_args := !new_deprecated_args^str), "";

  "--force-sanity",
  Arg.Unit (fun () -> 
    debug "Force sanity??\n";
    let str = Printf.sprintf "--sanity yes " in
      new_deprecated_args := !new_deprecated_args^str), "";

  "--neutral-walk-pop-size",
  Arg.Int (fun runs -> 
    let str = Printf.sprintf "--popsize %d " runs in
      new_deprecated_args := !new_deprecated_args^str), "";

  "--uniq-cov",
  Arg.Unit (fun unit -> 
    let str = Printf.sprintf "--uniq " in
      new_deprecated_args := !new_deprecated_args^str), "";

  "--robustness-ops",
  Arg.String (fun ops -> 
    let str = ref "" in
      let do_op_p op = 
        try 
          ignore (String.index ops op); true 
        with Not_found -> false in
        if do_op_p 'a' then 
          str := "--appp 1.0 "
        else 
          str := "--appp 0.0 ";
        if do_op_p 'd' then
          str := !str^"--delp 1.0 "
        else 
          str := !str ^"--delp 0.0 ";
        if do_op_p 's' then
          str := !str^"--swapp 1.0 " 
        else 
          str := !str^"--swapp 0.0 ";
        new_deprecated_args :=!new_deprecated_args^(!str)), "";

  "--asm-sample-runs",
  Arg.Int (fun runs -> 
    let str = Printf.sprintf "--sample-runs %d " runs in
      new_deprecated_args := !new_deprecated_args^str), "";

  "--elf-sample-runs",
  Arg.Int (fun runs -> 
    let str = Printf.sprintf "--sample-runs %d " runs in
      new_deprecated_args := !new_deprecated_args^str), "";

  "--allow-sanity-fail",
  Arg.Unit (fun () -> 
    let str = Printf.sprintf "--sanity no " in
      new_deprecated_args := !new_deprecated_args^str), "";

  "--prepare",
  Arg.Unit (fun () -> 
    let str = Printf.sprintf "--generations 0 " in
      new_deprecated_args := !new_deprecated_args^str), "";
]

let usage_function aligned usage_msg x = 
  debug "usage: unknown option %s\n" x;
  Arg.usage aligned usage_msg; abort "usage"


(* Utility function to read 'command-line arguments' from a file. 
 * This allows us to avoid the old 'ldflags' file hackery, etc. *) 
let parse_options_in_file (file : string) : unit =
  let args = ref [ Sys.argv.(0) ] in 
  ( try
    let fin = open_in file in 
    (try while true do
      let line = input_line fin in
      if line <> "" && line.[0] <> '#' then begin 
        (* allow #comments *) 
        let words = Str.bounded_split space_regexp line 2 in 
        args := !args @ words 
      end 
    done with _ -> close_in fin) ;
  with e -> ()) ; 
  Arg.current := 0 ; 
  Arg.parse_argv (Array.of_list !args) 
    (Arg.align !options) 
    (fun str -> debug "%s: unknown option %s\n"  file str ; exit 1) usageMsg ;
  () 

(* Utility function to read 'command-line arguments' with some support for
 * deprecated arguments. *)
let parse_options_with_deprecated () : unit =
  let deprecated_usage arg = 
    Printf.printf "usage: the option %s is no longer supported and cannot be " arg ;
    Printf.printf "jury-rigged into the current implementation.\n";
    Printf.printf "\tit is likely that the functionality you are looking for no ";
    Printf.printf "longer exists, or has been moved into an external program (e.g.,";
    Printf.printf " the distributed GA server).\n";
    Printf.printf "\t revert back to an earlier version, consult documentation, ask";
    Printf.printf " someone, or implement the functionality you want ";
    Printf.printf "if you really need it\n";
    abort "usage: deprecated option %s\n" arg
  in
  let deprecated_warning arg =
    Printf.printf "WARNING: the argument %s is deprecated. This is not fatal, " arg;
    Printf.printf "as GenProg can handle certain deprecated options as of the March 2012 refactor.\n";
    Printf.printf "However, you may want to consult the GenProg documentation to avoid using \n";
    Printf.printf "deprecated options in the future, and verify that your config is doing what you\n";
    Printf.printf "think it is doing."
  in
  let to_parse_later = ref [] in 
  let deprecated = ref [Sys.argv.(0)] in
  let all_args = ref [] in
  let handleArg str = to_parse_later := !to_parse_later @ [str] in
  let rec get_args (remaining_args : string list) =
    match remaining_args with
      arg :: args when List.mem arg deprecated_but_ok -> 
        deprecated_warning arg;
        get_args args
    | arg :: args when List.mem arg deprecated_and_not_ok -> deprecated_usage arg
    | arg :: args when List.mem arg deprecated_options -> 
      deprecated_warning arg;
      if List.mem arg with_arg then begin
        deprecated := !deprecated @ [arg ; List.hd args];
        get_args (List.tl args)
      end else begin
        deprecated := !deprecated @ [arg];
        get_args args
      end
    | arg :: args -> all_args := !all_args @ [arg]; get_args args
    | [] -> ()
  in
    get_args (Array.to_list Sys.argv);
    let aligned = Arg.align !options in 
      
    (* first, parse the arguments, saving config files to parse *)
      Arg.parse_argv (Array.of_list !all_args) aligned handleArg usageMsg ; 

    (* now, parse each config file *)
      List.iter
        (fun file ->
          let args = ref [ Sys.argv.(0) ] in 
          let lines = 
          (* allow # comments *)
            List.filter (fun line -> line <> "" && line.[0] <> '#') (get_lines file)
          in
            List.iter
              (fun line ->
                let words = Str.bounded_split space_regexp line 2 in 
                  match List.hd words with
                    str when List.mem str deprecated_and_not_ok -> deprecated_usage str
                  | str when List.mem str deprecated_but_ok -> deprecated_warning str
                  | str when List.mem str deprecated_options ->
                    deprecated_warning str;
                    deprecated := !deprecated @ words
                  | _ -> args := !args @ words) lines;
            Arg.current := 0 ; 
          (* parse the arguments in this config file *)
            Arg.parse_argv (Array.of_list !args) 
              aligned (usage_function aligned usageMsg) usageMsg
        ) !to_parse_later;


    (* if some of the files contained deprecated arguments, handle these now *)
      if (List.length !deprecated) > 1 then begin
        Arg.current := 0 ; 
        let aligned = Arg.align deprecated_and_simulable in
        (* parse the deprecated arguments to construct a new string of arguments to parse again...*)
          new_deprecated_args := (Sys.argv.(0))^" ";
          Arg.parse_argv (Array.of_list !deprecated)
            aligned (usage_function aligned usageMsg) usageMsg;
          debug "new deprecated: %s\n" !new_deprecated_args;
          let args = Str.split whitespace_regexp !new_deprecated_args in
            Arg.current := 0 ; 
          (* ...and reparse *)
            let aligned = Arg.align !options in 
              Arg.parse_argv (Array.of_list args)
                aligned (usage_function aligned usageMsg) usageMsg
      end;
    (* now parse the command-line arguments again, so that they win
     * out over "./configuration" or whatnot *) 
      Arg.current := 0;
      Arg.parse_argv (Array.of_list !all_args) aligned handleArg usageMsg 

let replace_in_string base_string list_of_replacements = 
  List.fold_left (fun acc (literal,replacement) ->
    let regexp = Str.regexp (Str.quote literal) in
      Str.global_replace regexp replacement acc 
  ) base_string list_of_replacements 

module OrderedString =
struct
  type t = string
  let compare = compare
end

module StringMap = Map.Make(OrderedString)
module StringSet = Set.Make(OrderedString)

let map_cardinal map = 
  StringMap.fold (fun k v count -> count + 1) map 0

let mergemaps map1 map2 = 
  StringMap.fold
    (fun key ->
      fun v ->
        fun newmap ->
          StringMap.add key v newmap)
    map1 map2

module OrderedInt =
struct
  type t = int
  let compare = compare
end
module IntMap = Map.Make(OrderedInt)
module IntSet = Set.Make(OrderedInt)

module OrderedPairs = 
struct
  type t = int * int
  let compare (a1,a2) (b1,b2) =
    if a1 = b1 then compare a2 b2
    else compare a1 b1
end
module PairSet = Set.Make(OrderedPairs)

module OrderedWeights =
struct
  type t = int * float
  let compare (a1,a2) (b1,b2) = 
    if a2 = b2 then compare a1 b1
    else compare a2 b2
end

module WeightSet = Set.Make(OrderedWeights)

module OrderedStringType =
struct
  type t = string * Cil.typ
  let compare = compare
end
module StringTypeMap = Map.Make(OrderedStringType)

let clamp small value big =
  if value < small then small
  else if value > big then big
  else value 

(* Helper function for generating ranges *)
let (--) i j = 
  let rec aux n acc =
    if n < i then acc else aux (n-1) (n :: acc)
  in aux j []
    
let any_match regexp s = 
  try ignore (Str.search_forward regexp s 0); true with _   -> false
let does_match = any_match 

let pprintf = Printf.printf 
let spprintf = Printf.sprintf
let lfilt = List.filter
let lmap = List.map
let lfoldl = List.fold_left
let liter = List.iter
let llen = List.length
let lmem = List.mem
let lrev = List.rev
let lflat = List.flatten
let lflatmap fnc lst = List.flatten (List.map fnc lst)
let lmap2 = List.map2
let lfoldl2 = List.fold_left2
let lsort = List.sort
let hadd = Hashtbl.add 
let hrem = Hashtbl.remove
let hfind = Hashtbl.find
let hfold = Hashtbl.fold
let hiter = Hashtbl.iter
let hlen = Hashtbl.length
let hclear = Hashtbl.clear
let hmem = Hashtbl.mem
let hrep = Hashtbl.replace
let hcreate = Hashtbl.create

let hincr ht key = 
  let old = try hfind ht key with Not_found -> 0 in
    hrep ht key (old + 1)

let ht_find ht key new_val = 
  try 
    Hashtbl.find ht key 
  with Not_found -> 
    let newval = new_val () in
      hadd ht key newval; newval

let fst3 (a,_,_) = a
let snd3 (_,b,_) = b
let trd3 (_,_,c) = c

(* Memory Management and Debugging Functions *) 
let bytes_per_word = 
  if max_int = 1073741823 then 4 else 8 

let live_bytes () : int = 
  Gc.full_major () ; (* "will collect all currently unreacahble blocks" *) 
  let gc_stat = Gc.stat () in 
    gc_stat.Gc.live_words * bytes_per_word

let debug_size_in_bytes (x : 'a) : int = 
  let str = Marshal.to_string x [Marshal.Closures] in
    String.length str

let debug_size_in_mb (x : 'a) : float = 
  (float_of_int (debug_size_in_bytes x)) /. (1024.0 *. 1024.0) 

let choose_one_weighted (lst : ('a * float) list) : 'a * float =
  assert(lst <> []);
  let total_weight = List.fold_left (fun acc (sid,prob) ->
    acc +. prob) 0.0 lst in
    assert(total_weight > 0.0) ;
    let wanted = Random.float total_weight in
    let rec walk lst sofar =
      match lst with
      | [] -> failwith "choose_one_weighted"
      | (sid,prob) :: rest ->
        let here = sofar +. prob in
          if here >= wanted then (sid,prob)
          else walk rest here
    in
      walk lst 0.0

let get_opt opt = 
  match opt with
    Some(o) -> o | None -> failwith "Get_opt called on non-Some value."


(* CLG moved these here: potentially-deprecated options that she is proposing to
   remove in the March 2012 refactor.  I didn't want to lose them entirely in
   case they're up for debate, but I will probably remove them at some point
   once I've settled on their elimination. *)
(*let allow_sanity_fail = ref false 
let preprocess = ref false
let preprocess_command = ref "__COMPILER_NAME__ -E __SOURCE_NAME__ __COMPILER_OPTIONS__ > __OUT_NAME__"
let robustness_ops = ref "ads"
let uniq_coverage = ref false
let convert_swaps = ref false
let debug_put = ref false 
let apply_diff_script = ref ""
let output_binrep = ref false 
let delete_existing_subdirs = ref false
let coverage_outname = ref "coverage.path" 
let asm_sample_runs = ref 10
let elf_sample_runs = ref 10
let server = ref false
let prepare_rep = ref false
let use_canonical_source_sids = ref true 
let neutral_walk_pop_size = ref 100
let one_positive_path = ref false
let print_fix_info = ref ""
let print_line_numbers = ref false 
let print_func_lines = ref false 
let use_subatoms = ref false 
let skip_sanity = ref false
let force_sanity = ref false
let multi_file = ref false
let use_full_paths = ref false 
let use_subdirs = ref false
let neutral_walk_steps = ref 100
let suffix_extension = ref ".c"
let mutrb_runs = ref 1000
let neutral_fitness = ref 5.0
let recompute_path_weights = ref false
let mutp = ref 0.05

(* Not committing to this, just trying it out *)
let deprecated_options = [
  "--recompute-weights", Arg.Set recompute_path_weights, " recompute the path weighting scheme; for use with neg-weight and pos-weight";
  (* use number of positive tests, right? *)
  "--neutral", Arg.Set_float neutral_fitness, "X Neutral fitness";
  (* use generations instead *)
  "--mutrb-runs", Arg.Set_int mutrb_runs, "X evaluate neutrality of X runs of each mutation operation";
  "--neutral-walk-steps", Arg.Set_int neutral_walk_steps,
  "X Take X steps through the neutral space.";
  (* default for multi-file *)
  "--use-subdirs", Arg.Set use_subdirs, " use one subdirectory per variant.";
  (* ...just always use the full paths *)
  "--use-full-paths", Arg.Set use_full_paths, " use full pathnames";
  (* intuit this from usage *)
  "--multi-file", Arg.Set multi_file, "X program has multiple source files.  Will use separate subdirs."  ;
  (* just a sanity flag *)
  "--skip-sanity", Arg.Set skip_sanity, " skip sanity checking";
  "--force-sanity", Arg.Set force_sanity, " force sanity checking";
  (* set mutp > 0, no? *)
  "--use-subatoms", Arg.Set use_subatoms, " use subatoms (expression-level mutation)" ;
  "--print-func-lines", Arg.Set print_func_lines, " print start/end line numbers of all functions" ;
  (* I don't know why we ever would *)
  "--print-line-numbers", Arg.Set print_line_numbers, " do print CIL #line numbers" ;
  (* redundant with --coverage-info; remember to fix that, btw *)
  "--print-fix-info", Arg.Set_string print_fix_info, " translate the line file into a list of statements, print to file X.";
  "--one-pos", Arg.Set one_positive_path, " Run only one positive test case, typically for the sake of speed.";
  (* why in the name of the allmighty holy being do you need a separate population size? *)
  "--neutral-walk-pop-size", Arg.Set_int neutral_walk_pop_size,
  "X Walk a population of size X through the neutral space.";
  "--suffix-extension", Arg.Set_string suffix_extension, "X append X to source filename";
  (* I'm 99% confident that literally no one uses this *)
  "--no-canonify-sids", Arg.Clear use_canonical_source_sids, " keep identical source smts separate" ;
  (* separate main for server, like nht *)
  "--server", Arg.Set server, " This is server machine"   ;
  (* there's no really good reason to *not* replace existing subdirs *)
  "--delete-subdirs", Arg.Set delete_existing_subdirs, " recreate subdirectories if they already exist. Default: false";
  (* I actually don't think we need this since it's always renamed to .neg and .pos anyway *)
  "--coverage-out", Arg.Set_string coverage_outname, " where to put the path info when instrumenting source code for coverage.  Default: ./coverage.path";
  (* I think output_binrep will be dealt with via better serialization *)
  "--output-binrep", Arg.Set output_binrep, " output binary representations with source files";
  "--apply-diff", Arg.Set_string apply_diff_script, " Apply a diff script";
  "--debug-put", Arg.Set debug_put, " note each #put in a variant's name" ;
  "--convert-swaps", Arg.Set convert_swaps, " Convert swaps into two deletes and two appends before minimizing.";
  "--uniq-cov", Arg.Set uniq_coverage, " you should use --uniq instead";
  (* settable with the probabilities *)
  "--robustness-ops", Arg.Set_string robustness_ops, "X only test robustness of operations in X, e.g., 'ad' for 'append' and 'delete'" ;
  (* this was for me and I never used it *)
  "--preprocess", Arg.Set preprocess, " preprocess the C code before parsing. Def: false";
  "--preprocessor", Arg.Set_string preprocess_command, " preprocessor command.  Default: __COMPILER__ -E" ;
  (* just one: --sample-runs *)
  "--asm-sample-runs",  Arg.Set_int asm_sample_runs,  "X Execute X runs of the test suite while sampling with oprofile.";
  "--elf-sample-runs",
  Arg.Set_int elf_sample_runs,
  "X Execute X runs of the test suite while sampling with oprofile.";
  
  "--use-line-file", 
  Arg.Unit (fun () -> 
    raise (Arg.Bad " Deprecated.  For the same functionality, do \n \
                         \t\"--fault-scheme line\", \"--fault-file file_with_line_info.ext\"\n")), " --use-line-file is deprecated";
  "--use-path-file", Arg.Unit (fun () -> 
    raise (Arg.Bad " Deprecated; the behavior is default.  You can be explicit \
                     with \"--fault-scheme path\".  --regen-paths forces path regeneration. Overried the default path files with \
                      \"--fault-path/--fix-path path_files.ext\"")),
  " --use-path-file is deprecated.";
  (* CLG is considering deleting this since I can't think of a single case
     where we want it.  We certainly don't need it *and* --skip-sanity, I
     don't think, unless it's critical for the graphics stuff. *)
  "--allow-sanity-fail", Arg.Set allow_sanity_fail, " allow sanity checks to fail";
  (* set num_gens to 0 *)
  "--prepare", Arg.Set prepare_rep, " Prepare representation for repair, but don't actually try to repair it.";
    "--mutp", Arg.Set_float mutp, "X use X as mutation rate";


]
*)