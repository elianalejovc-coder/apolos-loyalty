import { useEffect, useMemo, useState } from 'react'
import { QRCodeSVG } from 'qrcode.react'
import { LogOut, Search, ShieldCheck, Ticket, UserRound, Users } from 'lucide-react'
import { supabase } from './lib/supabase'

type StaffRole = 'admin' | 'manager' | 'employee'

type StaffProfile = {
  user_id: string
  display_name: string
  role: StaffRole
  is_active: boolean
}

type CustomerResult = {
  customer_id: string
  display_name: string | null
  status: string
  cycle_number: number
  visits_in_cycle: number
  visits_required: number
  reward_id: string | null
  reward_status: 'available' | 'redeemed' | 'expired' | null
  reward_description: string | null
  issued_at: string | null
}

type Dashboard = {
  customer: { id: string; display_name: string | null }
  cycle_number: number
  visits_in_cycle: number
  visits_required: number
  reward: null | {
    id: string
    description: string
    status: string
    issued_at: string
    code: string
    qr_payload: string
  }
}

const errorText = (message: string) => {
  const map: Record<string, string> = {
    reward_pending: 'La recompensa anterior todavía está pendiente de canje.',
    visit_too_soon: 'Esta visita está dentro de la ventana mínima de 12 horas.',
    idempotency_conflict: 'La operación ya fue usada con otro cliente.',
    customer_not_found: 'Cliente no encontrado o bloqueado.',
    reward_already_redeemed: 'Esta recompensa ya fue canjeada.',
    staff_access_required: 'Tu cuenta no tiene acceso al panel de personal.',
    bootstrap_already_completed: 'El administrador inicial ya fue configurado.',
  }
  return map[message] ?? message
}

export default function App() {
  const [sessionReady, setSessionReady] = useState(false)
  const [userEmail, setUserEmail] = useState<string | null>(null)
  const [staff, setStaff] = useState<StaffProfile | null>(null)
  const [dashboard, setDashboard] = useState<Dashboard | null>(null)
  const [authEmail, setAuthEmail] = useState('')
  const [authSent, setAuthSent] = useState(false)
  const [authBusy, setAuthBusy] = useState(false)
  const [authError, setAuthError] = useState('')

  const loadIdentity = async () => {
    const { data } = await supabase.auth.getSession()
    const user = data.session?.user
    setUserEmail(user?.email ?? user?.phone ?? null)
    if (!user) {
      setStaff(null)
      setDashboard(null)
      setSessionReady(true)
      return
    }

    const { data: staffData } = await supabase
      .from('staff_profiles')
      .select('user_id, display_name, role, is_active')
      .eq('user_id', user.id)
      .maybeSingle()

    setStaff(staffData as StaffProfile | null)
    if (!staffData) {
      const { data: customerData } = await supabase.rpc('get_customer_dashboard')
      if (customerData) setDashboard(customerData as Dashboard)
    }
    setSessionReady(true)
  }

  useEffect(() => {
    void loadIdentity()
    const { data: listener } = supabase.auth.onAuthStateChange(() => void loadIdentity())
    return () => listener.subscription.unsubscribe()
  }, [])

  const sendMagicLink = async () => {
    setAuthBusy(true)
    setAuthError('')
    const email = authEmail.trim().toLowerCase()
    if (!email) {
      setAuthError('Escribe un correo.')
      setAuthBusy(false)
      return
    }
    const { error } = await supabase.auth.signInWithOtp({
      email,
      options: { emailRedirectTo: window.location.origin },
    })
    if (error) setAuthError(error.message)
    else setAuthSent(true)
    setAuthBusy(false)
  }

  const logout = async () => {
    await supabase.auth.signOut()
    setStaff(null)
    setDashboard(null)
    setUserEmail(null)
  }

  if (!sessionReady) return <div className="shell loading">Cargando Apolo’s Loyalty…</div>

  if (!userEmail) {
    return (
      <div className="shell auth-shell">
        <div className="brand-mark">☼</div>
        <p className="eyebrow">APOLO’S LOYALTY</p>
        <h1>Tu visita cuenta.</h1>
        <p className="muted">Accede con un enlace mágico. No necesitas instalar una aplicación.</p>
        <div className="auth-card">
          <label htmlFor="email">Correo electrónico</label>
          <input id="email" value={authEmail} onChange={(event) => setAuthEmail(event.target.value)} placeholder="tu@email.com" type="email" />
          <button className="primary" onClick={() => void sendMagicLink()} disabled={authBusy}>{authBusy ? 'Enviando…' : 'Enviar enlace'}</button>
          {authSent && <p className="success">Revisa tu correo para entrar.</p>}
          {authError && <p className="error">{errorText(authError)}</p>}
        </div>
        <p className="fine-print">El QR público nunca registra una visita. Las visitas solo se registran desde el panel autorizado.</p>
      </div>
    )
  }

  if (staff) return <StaffApp staff={staff} email={userEmail} onLogout={() => void logout()} />
  return <CustomerApp dashboard={dashboard} email={userEmail} onLogout={() => void logout()} onRefresh={() => void loadIdentity()} />
}

function CustomerApp({ dashboard, email, onLogout, onRefresh }: { dashboard: Dashboard | null; email: string; onLogout: () => void; onRefresh: () => void }) {
  const [name, setName] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [created, setCreated] = useState(false)

  const createProfile = async () => {
    setBusy(true)
    setError('')
    const { error: rpcError } = await supabase.rpc('ensure_customer_profile', { p_display_name: name.trim() || null })
    if (rpcError) setError(errorText(rpcError.message))
    else {
      setCreated(true)
      onRefresh()
    }
    setBusy(false)
  }

  if (!dashboard && !created) {
    return (
      <div className="shell auth-shell">
        <p className="eyebrow">NUEVO CLIENTE</p>
        <h1>Empieza tu ciclo.</h1>
        <p className="muted">Tu cuenta queda vinculada a tu correo para que puedas recuperar tu progreso desde otro teléfono.</p>
        <div className="auth-card">
          <label htmlFor="name">Nombre</label>
          <input id="name" value={name} onChange={(event) => setName(event.target.value)} placeholder="Tu nombre" />
          <button className="primary" onClick={() => void createProfile()} disabled={busy}>{busy ? 'Creando…' : 'Crear mi tarjeta'}</button>
          {error && <p className="error">{error}</p>}
        </div>
        <button className="link-button" onClick={onLogout}>Cerrar sesión · {email}</button>
      </div>
    )
  }

  if (!dashboard) return <div className="shell loading">Preparando tu tarjeta…</div>
  const percent = Math.min(100, Math.round((dashboard.visits_in_cycle / dashboard.visits_required) * 100))

  return (
    <div className="shell customer-shell">
      <header className="topbar"><div><p className="eyebrow">APOLO’S LOYALTY</p><strong>Hola, {dashboard.customer.display_name || 'cliente'}</strong></div><button className="icon-button" onClick={onLogout} aria-label="Cerrar sesión"><LogOut size={18} /></button></header>
      <main>
        <section className="hero-card">
          <div><p className="eyebrow">CICLO {dashboard.cycle_number}</p><h1>{dashboard.visits_in_cycle} / {dashboard.visits_required}</h1><p className="muted">visitas válidas</p></div>
          <div className="sun">☼</div>
        </section>
        <div className="progress"><span style={{ width: `${percent}%` }} /></div>
        <section className="stamp-grid" aria-label="Progreso de visitas">
          {Array.from({ length: dashboard.visits_required }, (_, index) => <div className={`stamp ${index < dashboard.visits_in_cycle ? 'filled' : ''}`} key={index}>{index < dashboard.visits_in_cycle ? '✓' : index + 1}</div>)}
        </section>
        {dashboard.reward ? (
          <section className="reward-card">
            <div className="reward-copy"><p className="eyebrow">RECOMPENSA DISPONIBLE</p><h2>{dashboard.reward.description}</h2><p className="fine-print">Muestra este QR al personal para canjearla. Solo puede utilizarse una vez.</p></div>
            <div className="qr-wrap"><QRCodeSVG value={dashboard.reward.qr_payload} size={156} includeMargin /><code>{dashboard.reward.code.slice(0, 13)}</code></div>
          </section>
        ) : <section className="info-card"><Ticket size={22} /><div><strong>Tu próxima recompensa</strong><p>Completa las {dashboard.visits_required} visitas para desbloquearla.</p></div></section>}
      </main>
      <footer>Cuenta: {email}</footer>
    </div>
  )
}

function StaffApp({ staff, email, onLogout }: { staff: StaffProfile; email: string; onLogout: () => void }) {
  const [query, setQuery] = useState('')
  const [results, setResults] = useState<CustomerResult[]>([])
  const [selected, setSelected] = useState<CustomerResult | null>(null)
  const [message, setMessage] = useState('')
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)
  const [showAdmin, setShowAdmin] = useState(false)

  const search = async () => {
    setBusy(true); setError(''); setMessage('')
    const { data, error: rpcError } = await supabase.rpc('search_customers', { p_search: query.trim() })
    if (rpcError) setError(errorText(rpcError.message))
    else setResults((data ?? []) as CustomerResult[])
    setBusy(false)
  }

  const recordVisit = async (customer: CustomerResult, override = false) => {
    setBusy(true); setError(''); setMessage('')
    const { data, error: rpcError } = await supabase.rpc('record_visit', {
      p_customer_id: customer.customer_id,
      p_idempotency_key: crypto.randomUUID(),
      p_note: null,
      p_override_reason: override ? 'Override autorizado desde panel' : null,
    })
    if (rpcError) setError(errorText(rpcError.message))
    else {
      const result = data as { reward_id?: string | null; visits_in_cycle?: number; reward_code?: string | null }
      setMessage(result.reward_id ? `Visita registrada. Recompensa disponible: ${result.reward_code}` : `Visita registrada. ${result.visits_in_cycle ?? 0} visitas en el ciclo.`)
      await search()
    }
    setBusy(false)
  }

  const redeem = async (rewardId: string) => {
    setBusy(true); setError(''); setMessage('')
    const { error: rpcError } = await supabase.rpc('redeem_reward', { p_reward_id: rewardId })
    if (rpcError) setError(errorText(rpcError.message))
    else { setMessage('Recompensa canjeada correctamente.'); await search() }
    setBusy(false)
  }

  const canOverride = staff.role === 'admin' || staff.role === 'manager'
  const canManageStaff = staff.role === 'admin'

  return (
    <div className="shell staff-shell">
      <header className="topbar"><div><p className="eyebrow">APOLO’S · STAFF</p><strong>{staff.display_name}</strong><span className="role-pill">{staff.role}</span></div><button className="icon-button" onClick={onLogout}><LogOut size={18} /></button></header>
      <main>
        <section className="admin-hero"><div><p className="eyebrow">PANEL OPERATIVO</p><h1>Clientes & visitas</h1><p className="muted">Registra únicamente visitas válidas y controla recompensas desde el servidor.</p></div><ShieldCheck size={42} /></section>
        <div className="search-row"><input value={query} onChange={(event) => setQuery(event.target.value)} onKeyDown={(event) => { if (event.key === 'Enter') void search() }} placeholder="Nombre o ID del cliente" /><button className="primary compact" onClick={() => void search()} disabled={busy}><Search size={17} /> Buscar</button></div>
        {message && <p className="success banner">{message}</p>}
        {error && <p className="error banner">{error}</p>}
        <section className="customer-list">
          {results.map((customer) => <CustomerRow key={customer.customer_id} customer={customer} onSelect={() => setSelected(customer)} onVisit={() => void recordVisit(customer)} onOverride={() => void recordVisit(customer, true)} canOverride={canOverride} onRedeem={() => customer.reward_id ? void redeem(customer.reward_id) : undefined} busy={busy} />)}
          {!results.length && <div className="empty"><Users size={30} /><p>Busca un cliente para empezar.</p></div>}
        </section>
        {selected && <section className="detail-card"><button className="link-button" onClick={() => setSelected(null)}>Cerrar detalle</button><h2>{selected.display_name || 'Cliente sin nombre'}</h2><code>{selected.customer_id}</code><p>Ciclo {selected.cycle_number} · {selected.visits_in_cycle}/{selected.visits_required} visitas</p></section>}
        {canManageStaff && <button className="secondary admin-toggle" onClick={() => setShowAdmin(!showAdmin)}><ShieldCheck size={17} /> {showAdmin ? 'Ocultar administración' : 'Administrar personal'}</button>}
        {showAdmin && <StaffManagement />}
      </main>
      <footer>Sesión: {email} · Rol: {staff.role}</footer>
    </div>
  )
}

function CustomerRow({ customer, onSelect, onVisit, onOverride, onRedeem, canOverride, busy }: { customer: CustomerResult; onSelect: () => void; onVisit: () => void; onOverride: () => void; onRedeem: () => void; canOverride: boolean; busy: boolean }) {
  const rewardAvailable = customer.reward_status === 'available' && Boolean(customer.reward_id)
  const visitLabel = useMemo(() => rewardAvailable ? 'Recompensa pendiente' : `${customer.visits_in_cycle}/${customer.visits_required}`, [customer.visits_in_cycle, customer.visits_required, rewardAvailable])
  return <article className="customer-row"><button className="customer-main" onClick={onSelect}><UserRound size={20} /><span><strong>{customer.display_name || 'Sin nombre'}</strong><small>{visitLabel} · ciclo {customer.cycle_number}</small></span></button><div className="row-actions">{rewardAvailable ? <button className="primary compact" onClick={onRedeem} disabled={busy}>Canjear</button> : <button className="primary compact" onClick={onVisit} disabled={busy}>+ Visita</button>}{canOverride && !rewardAvailable && <button className="ghost compact" onClick={onOverride} disabled={busy}>Override</button>}</div></article>
}

function StaffManagement() {
  const [profiles, setProfiles] = useState<StaffProfile[]>([])
  const [message, setMessage] = useState('')
  const load = async () => {
    const { data } = await supabase.rpc('list_staff_profiles')
    setProfiles((data ?? []) as StaffProfile[])
  }
  useEffect(() => { void load() }, [])
  return <section className="management-card"><h2>Personal</h2><p className="muted">Crea usuarios en Supabase Auth primero; después asígnales rol desde esta capa.</p>{profiles.map((profile) => <div className="staff-row" key={profile.user_id}><span><strong>{profile.display_name}</strong><small>{profile.role} · {profile.is_active ? 'activo' : 'inactivo'}</small></span></div>)}{message && <p className="success">{message}</p>}</section>
}
