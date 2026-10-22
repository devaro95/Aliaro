# Aliaro — Plantillas de email de Supabase Auth (es / en según idioma)

Dónde: Supabase → Authentication → Emails → Templates (en **Dev** y en **prod**, las mismas).
El idioma sale de `user_metadata.locale`, que la app guarda al registrarse y mantiene al día en cada inicio de sesión (`AuthSession.syncLocaleIfNeeded`). `"es"` → español; cualquier otro valor o vacío → inglés (misma regla que las push).
El código sale de `{{ .Token }}` (no lleva enlace).

---

## 1. Confirm signup

**Subject**

```
{{ if eq .Data.locale "es" }}Tu código de Aliaro: {{ .Token }}{{ else }}Your Aliaro code: {{ .Token }}{{ end }}
```

**Body (HTML)**

```html
{{ if eq .Data.locale "es" }}
<div style="background:#f6f6f4;padding:32px 16px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#111;">
  <div style="max-width:480px;margin:0 auto;background:#ffffff;border-radius:16px;padding:32px 28px;">
    <p style="margin:0 0 24px;font-size:22px;font-weight:700;letter-spacing:-0.02em;">Aliaro</p>
    <p style="margin:0 0 8px;font-size:16px;font-weight:600;">Confirma tu email</p>
    <p style="margin:0 0 20px;font-size:14px;line-height:1.5;color:#444;">Introduce este código en la app para terminar de crear tu cuenta:</p>
    <p style="margin:0 0 20px;padding:16px;background:#f6f6f4;border-radius:12px;text-align:center;font-size:30px;font-weight:700;letter-spacing:6px;font-family:'SF Mono',Menlo,Consolas,monospace;">{{ .Token }}</p>
    <p style="margin:0;font-size:13px;line-height:1.5;color:#777;">Si no has creado una cuenta en Aliaro, ignora este email.</p>
  </div>
  <p style="max-width:480px;margin:16px auto 0;text-align:center;font-size:12px;color:#999;">Aliaro · devaroapps.com</p>
</div>
{{ else }}
<div style="background:#f6f6f4;padding:32px 16px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#111;">
  <div style="max-width:480px;margin:0 auto;background:#ffffff;border-radius:16px;padding:32px 28px;">
    <p style="margin:0 0 24px;font-size:22px;font-weight:700;letter-spacing:-0.02em;">Aliaro</p>
    <p style="margin:0 0 8px;font-size:16px;font-weight:600;">Confirm your email</p>
    <p style="margin:0 0 20px;font-size:14px;line-height:1.5;color:#444;">Enter this code in the app to finish creating your account:</p>
    <p style="margin:0 0 20px;padding:16px;background:#f6f6f4;border-radius:12px;text-align:center;font-size:30px;font-weight:700;letter-spacing:6px;font-family:'SF Mono',Menlo,Consolas,monospace;">{{ .Token }}</p>
    <p style="margin:0;font-size:13px;line-height:1.5;color:#777;">If you didn't create an Aliaro account, you can ignore this email.</p>
  </div>
  <p style="max-width:480px;margin:16px auto 0;text-align:center;font-size:12px;color:#999;">Aliaro · devaroapps.com</p>
</div>
{{ end }}
```

---

## 2. Reset Password

**Subject**

```
{{ if eq .Data.locale "es" }}Recupera tu contraseña de Aliaro: {{ .Token }}{{ else }}Reset your Aliaro password: {{ .Token }}{{ end }}
```

**Body (HTML)**

```html
{{ if eq .Data.locale "es" }}
<div style="background:#f6f6f4;padding:32px 16px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#111;">
  <div style="max-width:480px;margin:0 auto;background:#ffffff;border-radius:16px;padding:32px 28px;">
    <p style="margin:0 0 24px;font-size:22px;font-weight:700;letter-spacing:-0.02em;">Aliaro</p>
    <p style="margin:0 0 8px;font-size:16px;font-weight:600;">Recupera tu contraseña</p>
    <p style="margin:0 0 20px;font-size:14px;line-height:1.5;color:#444;">Introduce este código en la app para elegir una contraseña nueva:</p>
    <p style="margin:0 0 20px;padding:16px;background:#f6f6f4;border-radius:12px;text-align:center;font-size:30px;font-weight:700;letter-spacing:6px;font-family:'SF Mono',Menlo,Consolas,monospace;">{{ .Token }}</p>
    <p style="margin:0;font-size:13px;line-height:1.5;color:#777;">Si no lo has pedido tú, ignora este email: tu contraseña no cambiará.</p>
  </div>
  <p style="max-width:480px;margin:16px auto 0;text-align:center;font-size:12px;color:#999;">Aliaro · devaroapps.com</p>
</div>
{{ else }}
<div style="background:#f6f6f4;padding:32px 16px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#111;">
  <div style="max-width:480px;margin:0 auto;background:#ffffff;border-radius:16px;padding:32px 28px;">
    <p style="margin:0 0 24px;font-size:22px;font-weight:700;letter-spacing:-0.02em;">Aliaro</p>
    <p style="margin:0 0 8px;font-size:16px;font-weight:600;">Reset your password</p>
    <p style="margin:0 0 20px;font-size:14px;line-height:1.5;color:#444;">Enter this code in the app to choose a new password:</p>
    <p style="margin:0 0 20px;padding:16px;background:#f6f6f4;border-radius:12px;text-align:center;font-size:30px;font-weight:700;letter-spacing:6px;font-family:'SF Mono',Menlo,Consolas,monospace;">{{ .Token }}</p>
    <p style="margin:0;font-size:13px;line-height:1.5;color:#777;">If you didn't ask for this, ignore this email — your password won't change.</p>
  </div>
  <p style="max-width:480px;margin:16px auto 0;text-align:center;font-size:12px;color:#999;">Aliaro · devaroapps.com</p>
</div>
{{ end }}
```

---

## Comprobar después

1. Compilar la app (cambio en `Core/AuthSession.swift`: `locale` en el registro + sincronización al iniciar sesión).
2. Dev, con el iPhone en español: registrar un email nuevo y usar "¿Has olvidado tu contraseña?" → ambos en español. Cambiar el idioma del iPhone a inglés, abrir la app (sincroniza `locale`) y pedir otro reset → en inglés.
3. Prod: lo mismo (cierra también "probar envío en prod").
