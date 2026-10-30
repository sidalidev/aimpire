extends RefCounted
# Calculs de la caméra du téléphone (docs/MOBILE-PORTRAIT.md §3.3), sans nœud : point au sol sous le doigt, butée
# élastique, ressort amorti, glissé avec inertie, limite lointaine, zoom souple, vitesse mesurée. Tout est statique, la
# taille de la vue est passée en paramètre : tests/test_camera_portrait.gd les vérifie sans fenêtre.

const HFOV := 30.0           # champ horizontal en portrait (degrés, KEEP_WIDTH)
const PITCH := 55.0          # plongée en portrait (degrés sous l'horizon)
const D_NEAR := 18.0         # un bâtiment de 3,6 unités occupe le tiers de la largeur
const D_BUILDING := 30.0     # cadrage d'une session (cockpit)
const D_VILLAGE := 58.0      # une parcelle de 28 unités remplit 90 % de la largeur
const D_FAR_MIN := 70.0
const D_FAR_MAX := 300.0
const R_MIN := 24.0          # rayon occupé minimal : le Forum et ses abords
const MARGE_PARCELLE := 14.0 # murs d'une parcelle (13,5) et une marge
const TAU_GLISSE := 0.325    # s : un lancer parcourt v0 × TAU
const TAU_SORTIE := 0.06     # s : hors limites, la part sortante de la vitesse s'éteint vite
const RESSORT_W := TAU / 0.4 # ressort amorti critique du retour dans les limites (environ 0,35 s)
const ELASTIQUE_ZOOM := 0.13976194   # ln(1,15) : dépassement maximal du zoom, en espace logarithmique
const ELASTIQUE_BORD := 0.12 # part de la largeur visible : dépassement maximal du bord du monde
const LANCER_MIN := 150.0    # dp/s
const ARRET := 10.0          # dp/s
const VITESSE_MAX := 6000.0  # dp/s
const FENETRE_VITESSE := 0.1 # s : la vitesse se mesure sur les 100 dernières ms
const DUREE_MIN_VITESSE := 0.016
const REPOS_AVANT_LEVER := 0.05   # s : doigt immobile avant de se lever, pas de lancer

# Point du sol (y = 0) sous un rayon, ou null près de l'horizon.
static func sol(origine: Vector3, direction: Vector3) -> Variant:
	if direction.y > -0.05:
		return null
	return origine + direction * (-origine.y / direction.y)

# Point du sol sous un point de l'écran (unités de la vue, comme event.position), avec la caméra telle qu'elle est.
static func ground_point(cam: Camera3D, s: Vector2) -> Variant:
	return sol(cam.project_ray_origin(s), cam.project_ray_normal(s))

# Direction (repère monde) du rayon d'une caméra en perspective de base `b`, pour un point `s` d'une vue `vue`.
# Même calcul que Camera3D.project_ray_normal, mais avec la taille de vue en paramètre (tests).
static func rayon(b: Basis, fov_deg: float, garde_largeur: bool, vue: Vector2, s: Vector2) -> Vector3:
	var t := tan(deg_to_rad(fov_deg) / 2.0)
	var tx := t if garde_largeur else t * vue.x / vue.y
	var ty := t * vue.y / vue.x if garde_largeur else t
	var n := Vector2(2.0 * s.x / vue.x - 1.0, 1.0 - 2.0 * s.y / vue.y)
	return (b * Vector3(n.x * tx, n.y * ty, -1.0)).normalized()

# Demi-largeur angulaire : tan(champ horizontal / 2) pour une vue donnée.
static func tan_demi_h(fov_deg: float, garde_largeur: bool, vue: Vector2) -> float:
	var t := tan(deg_to_rad(fov_deg) / 2.0)
	return t if garde_largeur else t * vue.x / maxf(vue.y, 1.0)

# Largeur visible au pivot (unités du monde) pour une distance d.
static func largeur_visible(d: float, fov_deg: float, garde_largeur: bool, vue: Vector2) -> float:
	return 2.0 * d * tan_demi_h(fov_deg, garde_largeur, vue)

# Élastique : un dépassement o devient m (1 - e^(-o/m)), jamais plus que m.
static func rubber(o: float, m: float) -> float:
	if m <= 0.0:
		return 0.0
	return m * (1.0 - exp(-o / m))

# Inverse de rubber : le dépassement brut qui donne le dépassement affiché e (reprise d'un geste pendant le retour
# élastique, sans saut). Au-delà de m (impossible par l'élastique), borné.
static func rubber_inverse(e: float, m: float) -> float:
	if m <= 0.0 or e <= 0.0:
		return maxf(e, 0.0)
	return -m * log(1.0 - minf(e / m, 0.999))

# Pivot affiché à partir du pivot brut : au-delà de r_bound, l'excès passe par l'élastique (radial).
static func pivot_borne(brut: Vector3, r_bound: float, o_max: float) -> Vector3:
	var r := Vector2(brut.x, brut.z).length()
	if r <= r_bound or r < 0.0001:
		return Vector3(brut.x, 0.0, brut.z)
	var k := (r_bound + rubber(r - r_bound, o_max)) / r
	return Vector3(brut.x * k, 0.0, brut.z * k)

# Rayon occupé par l'Empire et limite lointaine (toute la largeur de l'Empire à l'écran).
static func r_occ(villages: Array) -> float:
	var r := R_MIN
	for v in villages:
		r = maxf(r, Vector2(float(v.get("x", 0.0)), float(v.get("z", 0.0))).length() + MARGE_PARCELLE)
	return r

static func d_far(r: float) -> float:
	return clampf(1.08 * r / tan(deg_to_rad(HFOV / 2.0)), D_FAR_MIN, D_FAR_MAX)

# Zoom souple en espace logarithmique : z dans [ln d_min, ln d_max], au-delà l'élastique de ln 1,15.
static func soft_zoom(z: float, z_min: float, z_max: float) -> float:
	if z > z_max:
		return z_max + rubber(z - z_max, ELASTIQUE_ZOOM)
	if z < z_min:
		return z_min - rubber(z_min - z, ELASTIQUE_ZOOM)
	return z

# Ressort amorti critique, pas exact : x = valeur - cible, v = vitesse. Renvoie Vector2(x', v').
static func spring_step(x: float, v: float, w: float, dt: float) -> Vector2:
	var e := exp(-w * dt)
	return Vector2((x + (v + w * x) * dt) * e, (v - w * (v + w * x) * dt) * e)

# Un pas de glissé : vitesse amortie (constante TAU_GLISSE). `dehors` : direction radiale unitaire sortante quand le pivot
# est hors limites (sinon Vector3.ZERO), dont la part de vitesse s'éteint en TAU_SORTIE.
static func glide_step(v: Vector3, dt: float, dehors: Vector3) -> Vector3:
	var out := v * exp(-dt / TAU_GLISSE)
	if dehors != Vector3.ZERO:
		var radial := out.dot(dehors)
		if radial > 0.0:
			out -= dehors * radial * (1.0 - exp(-dt / TAU_SORTIE))
	return out

# Vitesse (unités par seconde, plan xz) d'après les échantillons Vector3(t, x, z) d'un tampon circulaire : ceux des
# FENETRE_VITESSE dernières secondes. `n` échantillons valides, `tete` = index du plus récent. ZERO si trop court.
static func velocity_from_samples(ech: PackedVector3Array, n: int, tete: int, maintenant: float) -> Vector2:
	if n < 2:
		return Vector2.ZERO
	var cap := ech.size()
	var dernier := ech[tete]
	var premier := dernier
	for i in range(1, n):
		var e := ech[(tete - i + cap) % cap]
		if maintenant - e.x > FENETRE_VITESSE:
			break
		premier = e
	var dt := dernier.x - premier.x
	if dt < DUREE_MIN_VITESSE:
		return Vector2.ZERO
	return Vector2(dernier.y - premier.y, dernier.z - premier.z) / dt

# Durée d'un vol de caméra : 0,3 à 0,6 s selon la distance rapportée à la largeur visible.
static func duree_vol(distance: float, largeur: float) -> float:
	return clampf(0.3 + 0.1 * log(1.0 + distance / maxf(largeur, 0.001)) / log(2.0), 0.3, 0.6)

static func cubique(u: float) -> float:
	u = clampf(u, 0.0, 1.0)
	return 4.0 * u * u * u if u < 0.5 else 1.0 - pow(-2.0 * u + 2.0, 3.0) / 2.0
