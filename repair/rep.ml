(* 
 * Program Repair Prototype (v2) 
 *
 * The "representation" interface handles:
 *   -> the program representation (e.g., CIL AST, ASM)
 *   -> gathering and storing fault localization (e.g., weighted path, 
 *      predicates)
 *   -> simple mutation operator building blocks (e.g., delete, 
 *      append, swap) 
 *
 * TODO:
 *  -> "Well-Typed" insert/delete/replace 
 *     (also, no moving "break" out of a loop) 
 *  -> repair templates 
 *  -> predicates
 *  -> asm 
 *
 *)
open Printf
open Global

(*
 * An atom is the smallest unit of our representation: a stmt in CIL,
 * a line of an ASM program, etc.  
 *)
type atom_id = int 
type test = Positive of int | Negative of int 

(*
 * This is the main interface for a program representation (e.g., CIL-AST,
 * Assembly, etc.). 
 *)
class type representation = object
  method copy : unit -> representation 
  method save_binary : string -> unit (* serialize to a disk file *)
  method load_binary : string -> unit (* desreialize *) 
  method from_source : string -> unit 
  method output_source : string -> unit 
  method sanity_check : unit -> unit 
  method compute_fault_localization : unit ->  unit 
  method compile : ?keep_source:bool -> string -> string -> bool 
  method test_case : test -> bool 
  method debug_info : unit ->  unit 
  method max_atom : unit -> atom_id (* 1 to N -- INCLUSIVE *) 
  method get_localization : unit -> (atom_id * float) list 
  method get_full_localization : unit -> (atom_id * float) list 
  method delete : atom_id -> unit 
  method append : atom_id -> atom_id -> unit 
  method swap : atom_id -> atom_id -> unit 
  method name : unit -> string 

end 

(*
 * A new representation can "inherit nullRep" and fill in features
 * as time goes by. 
 *)
class nullRep : representation = object
  method copy = failwith "copy" 
  method save_binary = failwith "save_binary" 
  method load_binary = failwith "load_binary" 
  method from_source = failwith "from_source" 
  method output_source = failwith "output_source" 
  method sanity_check = failwith "sanity_check" 
  method compute_fault_localization = failwith "fault_localization" 
  method compile = failwith "compile" 
  method test_case = failwith "test_case" 
  method debug_info = failwith "debug_info" 
  method max_atom = failwith "max_atom" 
  method get_localization = failwith "get_localization" 
  method get_full_localization = failwith "get_full_localization" 
  method delete = failwith "delete" 
  method append = failwith "append" 
  method swap = failwith "swap" 
  method name = failwith "name" 
end 

let compiler_name = ref "gcc" 
let compiler_options = ref "" 
let test_command = ref "./test.sh" 
let port = ref 808
let change_port () =
  port := (!port + 1) ;
  if !port > 1600 then 
    port := !port - 800 

let test_name t = match t with
  | Positive x -> sprintf "p%d" x
  | Negative x -> sprintf "n%d" x

let _ =
  options := !options @
  [
    "--compiler", Arg.Set_string compiler_name, "X use X as compiler";
    "--compiler-opts", Arg.Set_string compiler_options, "X use X as options";
    "--test-command", Arg.Set_string test_command, "X use X to run tests";
  ] 

(*
 * Persistent caching for test case evaluations. 
 *)
let test_cache = ref 
  ((Hashtbl.create 255) : (Digest.t, (test,bool) Hashtbl.t) Hashtbl.t)
let test_cache_query digest test = 
  if Hashtbl.mem !test_cache digest then begin
    let second_ht = Hashtbl.find !test_cache digest in
    try
      let res = Hashtbl.find second_ht test in
      Stats2.time "test_cache hit" (fun () -> Some(res)) () 
    with _ -> None 
  end else None 
let test_cache_add digest test result =
  let second_ht = 
    try
      Hashtbl.find !test_cache digest 
    with _ -> Hashtbl.create 7 
  in
  Hashtbl.replace second_ht test result ;
  Hashtbl.replace !test_cache digest second_ht 
let test_cache_save () = 
  let fout = open_out_bin "repair.cache" in 
  Marshal.to_channel fout (!test_cache) [] ; 
  close_out fout 
let test_cache_load () = 
  try 
    let fout = open_in_bin "repair.cache" in 
    test_cache := Marshal.from_channel fout ; 
    close_in fout 
  with _ -> () 

(* 
 * We track the number of unique test evaluations we've had to
 * do on this run, ignoring of the persistent cache.
 *)
let tested = (Hashtbl.create 4095 : ((Digest.t * test), unit) Hashtbl.t)
let num_test_evals_ignore_cache () = 
  let result = ref 0 in
  Hashtbl.iter (fun _ _ -> incr result) tested ;
  !result

let compile_failures = ref 0 

exception Test_Result of bool 
