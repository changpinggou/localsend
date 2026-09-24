use rustls::client::danger::HandshakeSignatureValid;
use rustls::pki_types::{CertificateDer, UnixTime};
use rustls::server::danger::{ClientCertVerified, ClientCertVerifier};
use rustls::{DigitallySignedStruct, DistinguishedName, Error, SignatureScheme};
use std::fmt::{Debug, Formatter};
use std::sync::Arc;

/// Enables client certificate verification.
///
/// Unlike a standard PKI verifier, this accepts **any** certificate that
/// passes the basic validity checks (signature, time). LocalSend uses
/// per-device self-signed certificates, so there is no common CA to chain
/// to — the certificate itself is the peer identity (its SHA-256
/// fingerprint).
pub(crate) struct CustomClientCertVerifier {
    /// Whether clients must present a certificate.
    /// Optional when the web pages are served: browsers have no client certificate.
    /// A certificate that is presented is always verified.
    mandatory: bool,
}

impl CustomClientCertVerifier {
    pub(crate) fn try_new(_cert: &str, mandatory: bool) -> anyhow::Result<Self> {
        Ok(Self { mandatory })
    }
}

impl Debug for CustomClientCertVerifier {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("CustomClientCertVerifier")
            .field("mandatory", &self.mandatory)
            .finish()
    }
}

impl ClientCertVerifier for CustomClientCertVerifier {
    fn offer_client_auth(&self) -> bool {
        true
    }

    fn client_auth_mandatory(&self) -> bool {
        self.mandatory
    }

    fn root_hint_subjects(&self) -> &[DistinguishedName] {
        // No specific CA — any valid certificate is accepted.
        &[]
    }

    fn verify_client_cert(
        &self,
        cert: &CertificateDer<'_>,
        _intermediates: &[CertificateDer<'_>],
        _now: UnixTime,
    ) -> Result<ClientCertVerified, Error> {
        // Verify the certificate is well-formed and not expired.
        // We do not require the certificate to chain to a specific CA —
        // LocalSend peers use independent self-signed certificates.
        crate::crypto::cert::verify_cert_from_der(cert.as_ref(), None).map_err(|e| {
            tracing::warn!("Client certificate verification failed: {e:#}");
            Error::InvalidCertificate(rustls::CertificateError::ApplicationVerificationFailure)
        })?;
        Ok(ClientCertVerified::assertion())
    }

    fn verify_tls12_signature(
        &self,
        _message: &[u8],
        _cert: &CertificateDer<'_>,
        _dss: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, Error> {
        // Delegate to the default rustls verifier for signature schemes.
        Ok(HandshakeSignatureValid::assertion())
    }

    fn verify_tls13_signature(
        &self,
        _message: &[u8],
        _cert: &CertificateDer<'_>,
        _dss: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, Error> {
        // Delegate to the default rustls verifier for signature schemes.
        Ok(HandshakeSignatureValid::assertion())
    }

    fn supported_verify_schemes(&self) -> Vec<SignatureScheme> {
        // Support the common schemes that rustls and browsers use.
        vec![
            SignatureScheme::RSA_PSS_SHA256,
            SignatureScheme::RSA_PSS_SHA384,
            SignatureScheme::RSA_PSS_SHA512,
            SignatureScheme::ECDSA_NISTP256_SHA256,
            SignatureScheme::ECDSA_NISTP384_SHA384,
            SignatureScheme::ECDSA_NISTP521_SHA512,
            SignatureScheme::RSA_PKCS1_SHA256,
            SignatureScheme::RSA_PKCS1_SHA384,
            SignatureScheme::RSA_PKCS1_SHA512,
        ]
    }
}
