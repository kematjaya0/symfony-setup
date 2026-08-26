import Link from 'next/link';

export default function AccessDeniedPage() {
    return (
        <div>
            <h1>Akses Ditolak</h1>
            <p>Kamu tidak punya izin untuk mengakses halaman ini.</p>
            <Link href="/dashboard">Kembali ke Dashboard</Link>
        </div>
    );
}
