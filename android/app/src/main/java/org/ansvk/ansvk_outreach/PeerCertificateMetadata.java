package org.ansvk.ansvk_outreach;

import java.io.ByteArrayInputStream;
import java.security.cert.CertificateFactory;
import java.security.cert.X509Certificate;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collection;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/** Parses the actual peer DER with the platform X.509 implementation. */
public final class PeerCertificateMetadata {
    private PeerCertificateMetadata() {}

    public static Map<String, Object> parse(byte[] der) throws Exception {
        if (der == null || der.length == 0 || der.length > 65536) {
            throw new IllegalArgumentException("Invalid certificate size");
        }
        X509Certificate certificate = (X509Certificate) CertificateFactory
                .getInstance("X.509").generateCertificate(new ByteArrayInputStream(der));
        if (!Arrays.equals(der, certificate.getEncoded())) {
            throw new IllegalArgumentException("Exactly one DER certificate required");
        }
        List<String> ipSans = new ArrayList<>();
        Collection<List<?>> entries = certificate.getSubjectAlternativeNames();
        if (entries != null) {
            for (List<?> entry : entries) {
                // Type 7 is iPAddress. DNS/CN text that looks like an IP is not an IP SAN.
                if (entry.size() == 2 && Integer.valueOf(7).equals(entry.get(0))
                        && entry.get(1) instanceof String) {
                    ipSans.add((String) entry.get(1));
                }
            }
        }
        Map<String, Object> result = new HashMap<>();
        result.put("notBefore", certificate.getNotBefore().getTime());
        result.put("notAfter", certificate.getNotAfter().getTime());
        result.put("ipSans", ipSans);
        return result;
    }
}
