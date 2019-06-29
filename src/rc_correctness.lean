import data.multiset
import data.finset

namespace list
open well_founded_tactics

-- sizeof_lt_sizeof_of_mem, map_wf, map_wf_eq_map & fn_body.rec_wf courtesy of Sebastian Ullrich
lemma sizeof_lt_sizeof_of_mem {α} [has_sizeof α] {a : α} : ∀ {l : list α}, a ∈ l → sizeof a < sizeof l
| []      h := absurd h (not_mem_nil _)
| (b::bs) h :=
  begin
    cases eq_or_mem_of_mem_cons h with h_1 h_2,
    subst h_1,
    {unfold_sizeof, cancel_nat_add_lt, trivial_nat_lt},
    {have aux₁ := sizeof_lt_sizeof_of_mem h_2,
     unfold_sizeof,
     exact nat.lt_add_left _ _ _ (nat.lt_add_left _ _ _ aux₁)}
  end

def map_wf {α β : Type*} [has_sizeof α] (xs : list α) (f : Π (a : α), (sizeof a < 1 + sizeof xs) → β) : list β :=
xs.attach.map (λ p,
  have sizeof p.val < 1 + sizeof xs, from nat.lt_add_left _ _ _ (list.sizeof_lt_sizeof_of_mem p.property),
  f p.val this)

lemma map_wf_eq_map {α β : Type*} [has_sizeof α] {xs : list α} {f : α → β} :
  map_wf xs (λ a _, f a) = map f xs :=
by simp [map_wf, attach, map_pmap, pmap_eq_map]
end list

namespace rc_correctness

def var := ℕ

def const := ℕ

def ctor := ℕ

inductive expr : Type
| const_app_full (c : const) (ys : list var) : expr
| const_app_part (c : const) (ys : list var) : expr
| var_app (x : var) (y : var) : expr
| ctor_app (i : ctor) (ys : list var) : expr
| proj (i : ctor) (x : var) : expr
| reset (x : var) : expr
| reuse (x : var) (i : ctor) (ys : list var) : expr

inductive fn_body : Type
| return (x : var) : fn_body 
| «let» (x : var) (e : expr) (F : fn_body) : fn_body
| case (x : var) (Fs : list fn_body) : fn_body
| inc (x : var) (F : fn_body) : fn_body
| dec (x : var) (F : fn_body) : fn_body

def {l} fn_body.rec_wf (C : fn_body → Sort l)
  (return : Π (x : var), C (fn_body.return x))
  («let» : Π (x : var) (e : expr) (F : fn_body) (F_ih : C F), C (fn_body.let x e F))
  (case : Π (x : var) (Fs : list fn_body) (Fs_ih : ∀ F ∈ Fs, C F), C (fn_body.case x Fs))
  (inc : Π (x : var) (F : fn_body) (F_ih : C F), C (fn_body.inc x F))
  (dec : Π (x : var) (F : fn_body) (F_ih : C F), C (fn_body.dec x F)) : Π (x : fn_body), C x
| (fn_body.return a) := return a
| (fn_body.let x a a_1) := «let» x a a_1 (fn_body.rec_wf a_1)
| (fn_body.case a a_1) := case a a_1 (λ a h,
  have sizeof a < 1 + sizeof a_1, from nat.lt_add_left _ _ _ (list.sizeof_lt_sizeof_of_mem h),
  fn_body.rec_wf a)
| (fn_body.inc a a_1) := inc a a_1 (fn_body.rec_wf a_1)
| (fn_body.dec a a_1) := dec a a_1 (fn_body.rec_wf a_1)

def FV_expr : expr → list var
| (expr.const_app_full _ xs) := xs
| (expr.const_app_part c xs) := xs
| (expr.var_app x y) := [x, y]
| (expr.ctor_app i xs) := xs
| (expr.proj c x) := [x]
| (expr.reset x) := [x]
| (expr.reuse x i xs) := xs ∪ [x]

def FV : fn_body → list var
| (fn_body.return x) := [x]
| (fn_body.let x e F) := FV_expr e ∪ (FV F).erase x
| (fn_body.case x Fs) := (Fs.map_wf (λ F h, FV F)).foldr (∪) []
| (fn_body.inc x F) := FV F ∪ [x]
| (fn_body.dec x F) := FV F ∪ [x]

structure fn := (ys : list var) (F : fn_body)

inductive rc : Type
| var : var → rc
| const : const → rc
| expr : expr → rc
| fn_body : fn_body → rc
| fn : fn → rc

instance var_to_rc : has_coe var rc := ⟨rc.var⟩ 

instance const_to_rc : has_coe var rc := ⟨rc.const⟩ 

instance expr_to_rc : has_coe expr rc := ⟨rc.expr⟩ 

instance fn_body_to_rc : has_coe fn_body rc := ⟨rc.fn_body⟩

instance fn_to_rc : has_coe fn rc := ⟨rc.fn⟩ 

def erase_rc_fn_body : fn_body → fn_body
| (fn_body.let _ (expr.reset _) F) := erase_rc_fn_body F
| (fn_body.let z (expr.reuse x i ys) F) := fn_body.let z (expr.ctor_app i ys) (erase_rc_fn_body F)
| (fn_body.let x e F) := fn_body.let x e (erase_rc_fn_body F)
| (fn_body.inc _ F) := erase_rc_fn_body F
| (fn_body.dec _ F) := erase_rc_fn_body F
| (fn_body.case x cases) := fn_body.case x (cases.map_wf (λ c h, erase_rc_fn_body c))
| (fn_body.return x) := fn_body.return x 

def erase_rc_fn (f : fn) : fn := ⟨f.ys, erase_rc_fn_body f.F⟩ 

@[derive decidable_eq]
inductive ob_lin_type : Type 
    | 𝕆 | 𝔹

@[derive decidable_eq]
inductive lin_type : Type
    | ob : ob_lin_type → lin_type
    | ℝ : lin_type

instance ob_lin_type_to_lin_type : has_coe ob_lin_type lin_type := ⟨lin_type.ob⟩

structure typed_rc := (c : rc) (ty : lin_type)

@[derive decidable_eq]
structure typed_var := (x : var) (ty : lin_type)

notation x ` ∶ `:2 τ := typed_var.mk x τ
notation xs ` [∶] `:2 τ := xs.map (∶ τ)
notation c ` ∷ `:2 τ := typed_rc.mk c τ 

abbreviation type_context := multiset typed_var

open ob_lin_type
open lin_type

inductive linear (β : const → var → ob_lin_type) : type_context → typed_rc → Prop
notation Γ ` ⊩ `:1 t := linear Γ t
| var (x : var) (τ : lin_type) : 
    [x ∶ τ] ⊩ x ∷ τ
| weaken (Γ : type_context) (t : typed_rc) (x : var) : 
    (Γ ⊩ t) 
    → (Γ + [x ∶ 𝔹] ⊩ t)
| contract (Γ : type_context) (x : var) (t : typed_rc) :
    (Γ + [x ∶ 𝔹, x ∶ 𝔹] ⊩ t)
    → (Γ + [x ∶ 𝔹] ⊩ t)
| inc_o (Γ : type_context) (x : var) (F : fn_body) :
    (Γ + [x ∶ 𝕆, x ∶ 𝕆] ⊩ F ∷ 𝕆)
    → (Γ + [x ∶ 𝕆] ⊩ fn_body.inc x F ∷ 𝕆)
| inc_b (Γ : type_context) (x : var) (F : fn_body) :
    (Γ + [x ∶ 𝔹, x ∶ 𝕆] ⊩ F ∷ 𝕆)
    → (Γ + [x ∶ 𝔹] ⊩ fn_body.inc x F ∷ 𝕆)
| dec_o (Γ : type_context) (x : var) (F : fn_body) :
    (Γ ⊩ F ∷ 𝕆)
    → (Γ + [x ∶ 𝕆] ⊩ fn_body.dec x F ∷ 𝕆)
| dec_r (Γ : type_context) (x : var) (F : fn_body) :
    (Γ ⊩ F ∷ 𝕆)
    → (Γ + [x ∶ ℝ] ⊩ fn_body.dec x F ∷ 𝕆)
| return (Γ : type_context) (x : var) :
    (Γ ⊩ x ∷ 𝕆)
    → (Γ ⊩ fn_body.return x ∷ 𝕆)
| case_o (Γ : type_context) (x : var) (Fs : list fn_body) :
    (∀ F ∈ Fs, Γ + [x ∶ 𝕆] ⊩ ↑F ∷ 𝕆)
    → (Γ + [x ∶ 𝕆] ⊩ fn_body.case x Fs ∷ 𝕆)
| case_b (Γ : type_context) (x : var) (Fs : list fn_body) :
    (∀ F ∈ Fs, Γ + [x ∶ 𝔹] ⊩ ↑F ∷ 𝕆)
    → (Γ + [x ∶ 𝔹] ⊩ fn_body.case x Fs ∷ 𝕆)
| const_app_full (Γys : list (type_context × var)) (c : const) :
    (∀ Γy ∈ Γys, (Γy : type_context × var).1 ⊩ Γy.2 ∷ β c Γy.2)
    → (multiset.join (Γys.map prod.fst) ⊩ expr.const_app_full c (Γys.map prod.snd) ∷ 𝕆)
| const_app_part (ys : list var) (c : const) :
    ys [∶] 𝕆 ⊩ expr.const_app_part c ys ∷ 𝕆
| var_app (x y : var) :
    [x ∶ 𝕆, y ∶ 𝕆] ⊩ expr.var_app x y ∷ 𝕆
| cnstr_app (ys : list var) (i : ctor) :
    ys [∶] 𝕆 ⊩ expr.ctor_app i ys ∷ 𝕆
| reset (x : var) :
    [x ∶ 𝕆] ⊩ expr.reset x ∷ ℝ
| reuse (x : var) (ys : list var) (i : ctor) :
    [x ∶ ℝ] + (ys [∶] 𝕆) ⊩ expr.reuse x i ys ∷ 𝕆
| let_o (Γ : type_context) (xs : list var) (e : expr) (Δ : type_context) (z : var) (F : fn_body) :
    (Γ + (xs [∶] 𝔹) ⊩ e ∷ 𝕆) → (Δ + (xs [∶] 𝕆) + [z ∶ 𝕆] ⊩ F ∷ 𝕆)
    → (Γ + Δ + (xs [∶] 𝕆) ⊩ fn_body.let z e F ∷ 𝕆)
| let_r (Γ : type_context) (xs : list var) (e : expr) (Δ : type_context) (z : var) (F : fn_body) :
    (Γ + (xs [∶] 𝔹) ⊩ e ∷ 𝕆) → (Δ + (xs [∶] 𝕆) + [z ∶ ℝ] ⊩ F ∷ 𝕆)
    → (Γ + Δ + (xs [∶] 𝕆) ⊩ fn_body.let z e F ∷ 𝕆)
| proj_bor (Γ : type_context) (x y : var) (F : fn_body) (i : ctor) :
    (Γ + [x ∶ 𝔹, y ∶ 𝔹] ⊩ F ∷ 𝕆)
    → (Γ + [x ∶ 𝔹] ⊩ fn_body.let y (expr.proj i x) F ∷ 𝕆)
| proj_own (Γ : type_context) (x y : var) (F : fn_body) (i : ctor) :
    (Γ + [x ∶ 𝕆, y ∶ 𝕆] ⊩ F ∷ 𝕆)
    → (Γ + [x ∶ 𝕆] ⊩ fn_body.let y (expr.proj i x) (fn_body.inc y F) ∷ 𝕆)

notation β `; ` Γ ` ⊩ `:1 t := linear β Γ t

inductive linear_const (β : const → var → ob_lin_type) (δ : const → fn) : const → Prop
notation ` ⊩ `:1 c := linear_const c
| const (c : const) :
    (β; (δ c).ys.map (λ y, y ∶ β c y) ⊩ (δ c).F ∷ 𝕆)
    → (⊩ c)

notation β `; ` δ ` ⊩ `:1 c := linear_const β δ c

inductive linear_program (β : const → var → ob_lin_type) (δ : const → fn) : (const → fn) → Prop
notation ` ⊩ `:1 δ := linear_program δ
| program (δᵣ : const → fn) :
    (∀ c : const, δᵣ c = erase_rc_fn (δ c) ∧ (β; δᵣ ⊩ c))
    → (⊩ δᵣ)

notation β `; ` δ ` ⊩ `:1 δᵣ := linear_program β δ δᵣ

def 𝕆plus (x : var) (V : list var) (F : fn_body) (βₗ : var → ob_lin_type) : fn_body :=
if βₗ x = 𝕆 ∧ x ∉ V then F else fn_body.inc x F

def 𝕆minus_var (x : var) (F : fn_body) (βₗ : var → ob_lin_type) : fn_body :=
if βₗ x = 𝕆 ∧ x ∉ FV F then fn_body.dec x F else F

def 𝕆minus : list var → fn_body → (var → ob_lin_type) → fn_body 
| [] F βₗ := F
| (x :: xs) F βₗ := 𝕆minus xs (𝕆minus_var x F βₗ) βₗ

def fn_update {α : Type} {β : Type} [decidable_eq α] (f : α → β) (a : α) (b : β) : α → β :=
    λ x, if x = a then b else f x

notation f `[` a `↦` b `]` := fn_update f a b 

def Capp : list (var × ob_lin_type) → fn_body → (var → ob_lin_type) → fn_body
| [] (fn_body.let z e F) βₗ := fn_body.let z e F
| ((y, t)::xs) (fn_body.let z e F) βₗ := 
    if t = 𝕆 then
        let ys := xs.map (λ ⟨x, b⟩, x) in 
            𝕆plus y (ys ∪ FV F) (Capp xs (fn_body.let z e F) βₗ) βₗ
    else
        Capp xs (fn_body.let z e (𝕆minus_var y F βₗ)) βₗ
| xs F βₗ := F

def C (β : const → var → ob_lin_type) : fn_body → (var → ob_lin_type) → fn_body
| (fn_body.return x) βₗ := 𝕆plus x ∅ (fn_body.return x) βₗ
| (fn_body.case x Fs) βₗ := let ys := FV (fn_body.case x Fs) in 
    fn_body.case x (Fs.map_wf (λ F h, 𝕆minus ys (C F βₗ) βₗ))
| (fn_body.let y (expr.proj i x) F) βₗ := 
    if βₗ x = 𝕆 then
        fn_body.let y (expr.proj i x) (fn_body.inc y (𝕆minus_var x (C F βₗ) βₗ))
    else
        fn_body.let y (expr.proj i x) (C F (βₗ[y ↦ 𝔹]))
| (fn_body.let y (expr.reset x) F) βₗ := fn_body.let y (expr.reset x) (C F βₗ)
| (fn_body.let z (expr.const_app_full c ys) F) βₗ := Capp (ys.map (λ y, ⟨y, β c y⟩)) (fn_body.let z (expr.const_app_full c ys) (C F βₗ)) βₗ
| (fn_body.let z (expr.const_app_part c ys) F) βₗ := 
    Capp (ys.map (λ y, ⟨y, 𝕆⟩)) (fn_body.let z (expr.const_app_part c ys) (C F βₗ)) βₗ
    -- here we ignore the first case to avoid proving non-termination. so far this should be equivalent, it may however cause issues down the road!
| (fn_body.let z (expr.var_app x y) F) βₗ := 
    Capp ([⟨x, 𝕆⟩, ⟨y, 𝕆⟩]) (fn_body.let z (expr.var_app x y) (C F βₗ)) βₗ   
| (fn_body.let z (expr.ctor_app i ys) F) βₗ :=
    Capp (ys.map (λ y, ⟨y, 𝕆⟩)) (fn_body.let z (expr.ctor_app i ys) (C F βₗ)) βₗ
| (fn_body.let z (expr.reuse x i ys) F) βₗ :=
    Capp (ys.map (λ y, ⟨y, 𝕆⟩)) (fn_body.let z (expr.reuse x i ys) (C F βₗ)) βₗ
| F βₗ := F

inductive expr_wf (δ : const → fn) : finset var → expr → Prop
notation Γ ` ⊢ `:1 e := expr_wf Γ e
| const_app_full (Γ : finset var) (ys : list var) (c : const) :
    (ys.length = (δ c).ys.length)
    → (Γ ∪ ys.to_finset ⊢ expr.const_app_full c ys)
| const_app_part (Γ : finset var) (c : const) (ys : list var) :
    (Γ ∪ ys.to_finset ⊢ expr.const_app_part c ys)
| var_app (Γ : finset var) (x y : var) :
    (Γ ∪ {x, y} ⊢ expr.var_app x y)
| ctor_app (Γ : finset var) (i : ctor) (ys : list var) : 
    (Γ ∪ ys.to_finset ⊢ expr.ctor_app i ys)
| proj (Γ : finset var) (x : var) (i : ctor) : 
    (Γ ∪ {x} ⊢ expr.proj i x)
| reset (Γ : finset var) (x : var) :
    (Γ ∪ {x} ⊢ expr.reset x)
| reuse (Γ : finset var) (x : var) (i : ctor) (ys : list var) :
    (Γ ∪ ys.to_finset ∪ {x} ⊢ expr.reuse x i ys)

notation δ `; ` Γ ` ⊢ `:1 e := expr_wf δ Γ e

inductive fn_body_wf (δ : const → fn) : finset var → fn_body → Prop
notation Γ ` ⊢ `:1 f := fn_body_wf Γ f
| return (Γ : finset var) (x : var) : (Γ ⊢ fn_body.return x) -- error in the paper: what is well-formedness of variables?
| «let» (Γ : finset var) (z : var) (e : expr) (F : fn_body) (xs : list var) :
    (δ; Γ ⊢ e) → (z ∈ FV F) → (z ∉ Γ) → (Γ ∪ {z} ⊢ F)
    → (Γ ⊢ fn_body.let z e F) -- NOTE: i removed the xs here.
| case (Γ : finset var) (x : var) (Fs : list fn_body):
    (∀ F ∈ Fs, Γ ∪ {x} ⊢ F)
    → (Γ ∪ {x} ⊢ fn_body.case x Fs)

notation δ `; ` Γ ` ⊢ `:1 f := fn_body_wf δ Γ f

inductive fn_wf (δ : const → fn) : fn → Prop
notation ` ⊢ `:1 f := fn_wf f
| fn (f : fn) : (δ; f.ys.to_finset ⊢ f.F) → (⊢ f)

notation δ ` ⊢ `:1 f := fn_wf δ f

inductive const_wf (δ : const → fn) : const → Prop
notation ` ⊢ `:1 c := const_wf c
| const (c : const) : (δ ⊢ δ c) → (⊢ c)

notation δ ` ⊢ `:1 c := const_wf δ c

inductive reuse_fn_body_wf : finset var → fn_body → Prop
notation Γ ` ⊢ᵣ `:1 f := reuse_fn_body_wf Γ f
| return (Γ : finset var) (x : var) : Γ ⊢ᵣ fn_body.return x
| let_reset (Γ : finset var) (z x : var) (F : fn_body) :
    (Γ ∪ {z} ⊢ᵣ F)
    → (Γ ⊢ᵣ fn_body.let z (expr.reset x) F)
| let_reuse (Γ : finset var) (z x : var) (F : fn_body) (i : ctor) (ys : list var) :
    (Γ ⊢ᵣ F)
    → (Γ ∪ {x} ⊢ᵣ fn_body.let z (expr.reuse x i ys) F)
| let_const_app_full (Γ : finset var) (F : fn_body) (z : var) (c : const) (ys : list var) :
    (Γ ⊢ᵣ F)
    → (Γ ⊢ᵣ fn_body.let z (expr.const_app_full c ys) F)
| let_const_app_part (Γ : finset var) (F : fn_body) (z : var) (c : const) (ys : list var) :
    (Γ ⊢ᵣ F)
    → (Γ ⊢ᵣ fn_body.let z (expr.const_app_part c ys) F)
| let_var_app (Γ : finset var) (F : fn_body) (z x y : var) :
    (Γ ⊢ᵣ F)
    → (Γ ⊢ᵣ fn_body.let z (expr.var_app x y) F)
| let_ctor_app (Γ : finset var) (F : fn_body) (z : var) (i : ctor) (ys : list var) :
    (Γ ⊢ᵣ F)
    → (Γ ⊢ᵣ fn_body.let z (expr.ctor_app i ys) F)
| let_proj (Γ : finset var) (F : fn_body) (z x : var) (i : ctor) :
    (Γ ⊢ᵣ F)
    → (Γ ⊢ᵣ fn_body.let z (expr.proj i x) F)
| case (Γ : finset var) (x : var) (Fs : list fn_body) :
    (∀ F ∈ Fs, Γ ⊢ᵣ F)
    → (Γ ⊢ᵣ fn_body.case x Fs)

notation Γ ` ⊢ᵣ `:1 f := reuse_fn_body_wf Γ f

inductive reuse_const_wf (δ : const → fn) : const → Prop
notation ` ⊢ᵣ `:1 c := reuse_const_wf c
| const (c : const) :
    (∅ ⊢ᵣ (δ c).F)
    → (⊢ᵣ c)

notation δ ` ⊢ᵣ `:1 c := reuse_const_wf δ c

end rc_correctness
