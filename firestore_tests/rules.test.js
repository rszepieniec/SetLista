// Testy reguł Firestore na lokalnym emulatorze: npm test
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, test } from 'node:test';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  Timestamp,
  arrayRemove,
  arrayUnion,
  deleteDoc,
  deleteField,
  orderBy,
  writeBatch,
  doc,
  getDoc,
  getDocs,
  query,
  serverTimestamp,
  setDoc,
  updateDoc,
  collection,
  where,
} from 'firebase/firestore';

let env;

const personalTeam = (uid) => ({
  name: 'Mój śpiewnik',
  ownerId: uid,
  personal: true,
  roles: { [uid]: 'owner' },
  memberIds: [uid],
  createdAt: serverTimestamp(),
});

const song = (uid, title = 'Cicha noc') => ({
  title,
  author: '',
  lyrics: 'Cicha noc, święta noc',
  updatedAt: serverTimestamp(),
  updatedBy: uid,
});

const db = (uid) => env.authenticatedContext(uid).firestore();

// Zespół "band" z trzema rolami, utworzony z pominięciem reguł.
async function seedBand() {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const admin = ctx.firestore();
    await setDoc(doc(admin, 'teams/band'), {
      name: 'Zespół',
      ownerId: 'olek',
      personal: false,
      roles: { olek: 'owner', ewa: 'editor', marek: 'member' },
      memberIds: ['olek', 'ewa', 'marek'],
      createdAt: new Date(),
    });
    await setDoc(doc(admin, 'teams/band/songs/s1'), {
      title: 'Barka',
      author: '',
      lyrics: 'Pan kiedyś stanął nad brzegiem',
      updatedAt: new Date(),
      updatedBy: 'olek',
    });
  });
}

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-setlista',
    firestore: { rules: readFileSync('../firestore.rules', 'utf8') },
  });
});

after(() => env.cleanup());

beforeEach(async () => {
  await env.clearFirestore();
  await seedBand();
});

describe('Mój śpiewnik', () => {
  test('użytkownik tworzy swój prywatny śpiewnik', async () => {
    await assertSucceeds(getDoc(doc(db('ala'), 'teams/personal_ala')));
    await assertSucceeds(setDoc(doc(db('ala'), 'teams/personal_ala'), personalTeam('ala')));
  });

  test('nie da się utworzyć prywatnego śpiewnika za kogoś innego', async () => {
    await assertFails(setDoc(doc(db('ala'), 'teams/personal_ola'), personalTeam('ala')));
    await assertFails(getDoc(doc(db('ala'), 'teams/personal_ola')));
  });

  test('nie da się dopisać innych osób przy tworzeniu', async () => {
    const team = { ...personalTeam('ala'), memberIds: ['ala', 'ola'] };
    await assertFails(setDoc(doc(db('ala'), 'teams/personal_ala'), team));
  });

  test('niezalogowany nic nie czyta', async () => {
    const anon = env.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(anon, 'teams/band')));
    await assertFails(getDocs(collection(anon, 'teams/band/songs')));
  });
});

describe('Zespół', () => {
  test('lista moich zespołów działa, cudzych nie widać', async () => {
    const mine = query(collection(db('marek'), 'teams'), where('memberIds', 'array-contains', 'marek'));
    await assertSucceeds(getDocs(mine));
    await assertFails(getDocs(collection(db('obcy'), 'teams')));
    await assertFails(getDoc(doc(db('obcy'), 'teams/band')));
  });

  test('member czyta piosenki, ale nie edytuje', async () => {
    await assertSucceeds(getDocs(collection(db('marek'), 'teams/band/songs')));
    await assertFails(setDoc(doc(db('marek'), 'teams/band/songs/s2'), song('marek')));
    await assertFails(deleteDoc(doc(db('marek'), 'teams/band/songs/s1')));
  });

  test('editor dodaje, edytuje i usuwa piosenki', async () => {
    const ewa = db('ewa');
    await assertSucceeds(setDoc(doc(ewa, 'teams/band/songs/s2'), song('ewa')));
    await assertSucceeds(setDoc(doc(ewa, 'teams/band/songs/s1/revisions/r1'), { title: 'Barka' }));
    await assertSucceeds(setDoc(doc(ewa, 'teams/band/songs/s1'), song('ewa', 'Barka (nowa)')));
    await assertSucceeds(deleteDoc(doc(ewa, 'teams/band/songs/s2')));
  });

  test('obcy nie widzi ani nie zmienia piosenek zespołu', async () => {
    await assertFails(getDocs(collection(db('obcy'), 'teams/band/songs')));
    await assertFails(setDoc(doc(db('obcy'), 'teams/band/songs/x'), song('obcy')));
  });

  test('piosenka musi mieć poprawne pola', async () => {
    const ewa = db('ewa');
    await assertFails(setDoc(doc(ewa, 'teams/band/songs/x'), { ...song('ewa'), title: '' }));
    await assertFails(setDoc(doc(ewa, 'teams/band/songs/x'), { ...song('ewa'), updatedBy: 'olek' }));
    await assertFails(setDoc(doc(ewa, 'teams/band/songs/x'), { ...song('ewa'), extra: 1 }));
  });

  test('historii wersji nie da się zmienić ani usunąć', async () => {
    await env.withSecurityRulesDisabled((ctx) =>
      setDoc(doc(ctx.firestore(), 'teams/band/songs/s1/revisions/r1'), { title: 'stara' }));
    await assertFails(setDoc(doc(db('olek'), 'teams/band/songs/s1/revisions/r1'), { title: 'x' }));
    await assertFails(deleteDoc(doc(db('olek'), 'teams/band/songs/s1/revisions/r1')));
  });

  test('owner i editor zmieniają nazwę, member nie; nikt nie dopisze się sam do zespołu', async () => {
    await assertSucceeds(updateDoc(doc(db('olek'), 'teams/band'), { name: 'Schola' }));
    await assertSucceeds(updateDoc(doc(db('ewa'), 'teams/band'), { name: 'Schola 2' }));
    await assertFails(updateDoc(doc(db('marek'), 'teams/band'), { name: 'X' }));
    // Editor zmienia tylko nazwę - nie role.
    await assertFails(updateDoc(doc(db('ewa'), 'teams/band'), { name: 'Y', 'roles.marek': 'editor' }));
    // Właściciel nie dopisze nikogo z pominięciem zaproszenia.
    await assertFails(updateDoc(doc(db('olek'), 'teams/band'), {
      'roles.obcy': 'editor',
      memberIds: arrayUnion('obcy'),
    }));
    await assertFails(updateDoc(doc(db('obcy'), 'teams/band'), {
      memberIds: ['olek', 'ewa', 'marek', 'obcy'],
    }));
  });

  test('prywatnego śpiewnika nie da się usunąć', async () => {
    await env.withSecurityRulesDisabled((ctx) =>
      setDoc(doc(ctx.firestore(), 'teams/personal_ala'), { ...personalTeam('ala'), createdAt: new Date() }));
    await assertFails(deleteDoc(doc(db('ala'), 'teams/personal_ala')));
    await assertSucceeds(deleteDoc(doc(db('olek'), 'teams/band')));
  });
});

// ---------- Zaproszenia, dołączanie, członkowie ----------

const inDays = (days) => Timestamp.fromMillis(Date.now() + days * 86400000);

async function seedInvite(code, { teamId = 'band', expiresAt = inDays(7) } = {}) {
  await env.withSecurityRulesDisabled((ctx) =>
    setDoc(doc(ctx.firestore(), `invites/${code}`), {
      teamId, teamName: 'Zespół', createdBy: 'olek', createdAt: new Date(), expiresAt,
    }));
}

function join(uid, code, teamId = 'band', { withMessage = false } = {}) {
  const store = db(uid);
  const batch = writeBatch(store);
  if (withMessage) {
    batch.set(doc(store, `teams/${teamId}/messages/joined-${uid}`), {
      type: 'joined', text: 'dołączył do zespołu', authorId: uid, authorName: 'Nowy',
      authorForm: 'm', createdAt: serverTimestamp(),
    });
  }
  batch.set(doc(store, `teams/${teamId}/joins/${uid}`), { code, joinedAt: serverTimestamp() });
  batch.update(doc(store, `teams/${teamId}`), {
    memberIds: arrayUnion(uid),
    [`roles.${uid}`]: 'editor',
    [`memberNames.${uid}`]: 'Nowy',
  });
  return batch.commit();
}

describe('Zaproszenia', () => {
  test('owner i editor tworzą zaproszenie, member i obcy nie', async () => {
    const invite = (by) => ({
      teamId: 'band', teamName: 'Zespół', createdBy: by,
      createdAt: serverTimestamp(), expiresAt: inDays(7),
    });
    await assertSucceeds(setDoc(doc(db('olek'), 'invites/ABCD2345'), invite('olek')));
    await assertSucceeds(setDoc(doc(db('ewa'), 'invites/EFGH2345'), invite('ewa')));
    await assertFails(setDoc(doc(db('marek'), 'invites/MNPQ2345'), invite('marek')));
    await assertFails(setDoc(doc(db('obcy'), 'invites/RSTU2345'), invite('obcy')));
    await assertFails(setDoc(doc(db('olek'), 'invites/LONG2345'), { ...invite('olek'), expiresAt: inDays(60) }));
  });

  test('kod da się odczytać, ale zaproszeń nie da się wylistować', async () => {
    await seedInvite('ABCD2345');
    await assertSucceeds(getDoc(doc(db('nowy'), 'invites/ABCD2345')));
    await assertFails(getDocs(collection(db('nowy'), 'invites')));
  });

  test('dołączenie z poprawnym kodem', async () => {
    await seedInvite('ABCD2345');
    await assertSucceeds(join('nowy', 'ABCD2345'));
    await assertSucceeds(getDocs(collection(db('nowy'), 'teams/band/songs')));
  });

  test('nie da się dołączyć bez kodu, z wygasłym lub z kodem innego zespołu', async () => {
    await seedInvite('OLD23456', { expiresAt: inDays(-1) });
    await seedInvite('OTHER234', { teamId: 'inny' });
    await assertFails(join('nowy', 'NIEMA234'));
    await assertFails(join('nowy', 'OLD23456'));
    await assertFails(join('nowy', 'OTHER234'));
    // Sama aktualizacja zespołu, bez zapisu kodu w joins:
    await assertFails(updateDoc(doc(db('nowy'), 'teams/band'), {
      memberIds: arrayUnion('nowy'), 'roles.nowy': 'editor',
    }));
  });

  test('dołączający nie nada sobie roli właściciela', async () => {
    await seedInvite('ABCD2345');
    const store = db('nowy');
    const batch = writeBatch(store);
    batch.set(doc(store, 'teams/band/joins/nowy'), { code: 'ABCD2345', joinedAt: serverTimestamp() });
    batch.update(doc(store, 'teams/band'), { memberIds: arrayUnion('nowy'), 'roles.nowy': 'owner' });
    await assertFails(batch.commit());
  });

  test('do prywatnego śpiewnika nie da się dołączyć', async () => {
    await env.withSecurityRulesDisabled((ctx) =>
      setDoc(doc(ctx.firestore(), 'teams/personal_ala'), { ...personalTeam('ala'), createdAt: new Date() }));
    await seedInvite('PRIV2345', { teamId: 'personal_ala' });
    await assertFails(join('nowy', 'PRIV2345', 'personal_ala'));
  });
});

describe('Członkowie', () => {
  test('editor opuszcza zespół, owner nie może', async () => {
    await assertSucceeds(updateDoc(doc(db('ewa'), 'teams/band'), {
      memberIds: arrayRemove('ewa'), 'roles.ewa': deleteField(),
    }));
    await assertFails(getDocs(collection(db('ewa'), 'teams/band/songs')));
    await assertFails(updateDoc(doc(db('olek'), 'teams/band'), {
      memberIds: arrayRemove('olek'), 'roles.olek': deleteField(),
    }));
  });

  test('owner zmienia role i usuwa członków', async () => {
    await assertSucceeds(updateDoc(doc(db('olek'), 'teams/band'), { 'roles.ewa': 'member' }));
    await assertFails(setDoc(doc(db('ewa'), 'teams/band/songs/x'), song('ewa')));
    await assertSucceeds(updateDoc(doc(db('olek'), 'teams/band'), {
      memberIds: arrayRemove('marek'), 'roles.marek': deleteField(),
    }));
    await assertFails(getDocs(collection(db('marek'), 'teams/band/songs')));
  });

  test('editor nie zmienia ról innych', async () => {
    await assertFails(updateDoc(doc(db('ewa'), 'teams/band'), { 'roles.marek': 'editor' }));
    await assertFails(updateDoc(doc(db('ewa'), 'teams/band'), { 'roles.ewa': 'owner' }));
  });

  test('owner nie może zostawić członka bez roli', async () => {
    await assertFails(updateDoc(doc(db('olek'), 'teams/band'), { 'roles.marek': deleteField() }));
  });

  test('każdy ustawia tylko swoje imię', async () => {
    await assertSucceeds(updateDoc(doc(db('marek'), 'teams/band'), { 'memberNames.marek': 'Marek' }));
    await assertFails(updateDoc(doc(db('marek'), 'teams/band'), { 'memberNames.ewa': 'Ewka' }));
  });
});

// ---------- Playlisty i czat ----------

const playlist = (uid) => ({
  name: 'Niedziela', date: null, songIds: ['s1'],
  createdBy: uid, createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
});

describe('Playlisty', () => {
  test('editor tworzy i zmienia playlistę, member tylko czyta', async () => {
    await assertSucceeds(setDoc(doc(db('ewa'), 'teams/band/playlists/p1'), playlist('ewa')));
    await assertSucceeds(updateDoc(doc(db('ewa'), 'teams/band/playlists/p1'), {
      songIds: ['s1', 's2'], date: Timestamp.now(), updatedAt: serverTimestamp(),
    }));
    await assertSucceeds(getDocs(collection(db('marek'), 'teams/band/playlists')));
    await assertFails(setDoc(doc(db('marek'), 'teams/band/playlists/p2'), playlist('marek')));
    await assertFails(deleteDoc(doc(db('marek'), 'teams/band/playlists/p1')));
  });

  test('nie da się podszyć pod autora ani zmienić daty utworzenia', async () => {
    await assertFails(setDoc(doc(db('ewa'), 'teams/band/playlists/p1'), playlist('olek')));
    await assertSucceeds(setDoc(doc(db('ewa'), 'teams/band/playlists/p1'), playlist('ewa')));
    await assertFails(updateDoc(doc(db('olek'), 'teams/band/playlists/p1'), {
      createdBy: 'olek', updatedAt: serverTimestamp(),
    }));
  });

  test('obcy nie widzi playlist', async () => {
    await assertFails(getDocs(collection(db('obcy'), 'teams/band/playlists')));
  });
});

describe('Czat', () => {
  const message = (uid, text = 'Próba o 18:00') => ({
    text, authorId: uid, authorName: uid, createdAt: serverTimestamp(),
  });

  test('każdy członek (także member) pisze i czyta', async () => {
    await assertSucceeds(setDoc(doc(db('marek'), 'teams/band/messages/m1'), message('marek')));
    await assertSucceeds(getDocs(query(collection(db('ewa'), 'teams/band/messages'), orderBy('createdAt', 'desc'))));
  });

  test('obcy nie pisze ani nie czyta', async () => {
    await assertFails(setDoc(doc(db('obcy'), 'teams/band/messages/m1'), message('obcy')));
    await assertFails(getDocs(collection(db('obcy'), 'teams/band/messages')));
  });

  test('nie da się pisać jako ktoś inny, edytować ani usuwać cudzych', async () => {
    await assertFails(setDoc(doc(db('marek'), 'teams/band/messages/m1'), message('olek')));
    await assertFails(setDoc(doc(db('marek'), 'teams/band/messages/m1'), message('marek', '')));
    await assertSucceeds(setDoc(doc(db('marek'), 'teams/band/messages/m1'), message('marek')));
    await assertFails(updateDoc(doc(db('marek'), 'teams/band/messages/m1'), { text: 'zmiana' }));
    await assertFails(deleteDoc(doc(db('ewa'), 'teams/band/messages/m1')));
    await assertSucceeds(deleteDoc(doc(db('marek'), 'teams/band/messages/m1')));
  });
});

// ---------- Komentarze i wiadomości-zdarzenia ----------

describe('Komentarze do piosenek', () => {
  const comment = (uid, text = 'Zaczynamy od refrenu') => ({
    text, authorId: uid, authorName: uid, createdAt: serverTimestamp(),
  });

  test('każdy członek komentuje, obcy nie widzi', async () => {
    await assertSucceeds(setDoc(doc(db('marek'), 'teams/band/songs/s1/comments/c1'), comment('marek')));
    await assertSucceeds(getDocs(collection(db('ewa'), 'teams/band/songs/s1/comments')));
    await assertFails(getDocs(collection(db('obcy'), 'teams/band/songs/s1/comments')));
    await assertFails(setDoc(doc(db('obcy'), 'teams/band/songs/s1/comments/c2'), comment('obcy')));
  });

  test('tylko autor usuwa; nie da się podszyć ani edytować', async () => {
    await assertFails(setDoc(doc(db('marek'), 'teams/band/songs/s1/comments/c1'), comment('ewa')));
    await assertSucceeds(setDoc(doc(db('marek'), 'teams/band/songs/s1/comments/c1'), comment('marek')));
    await assertFails(updateDoc(doc(db('marek'), 'teams/band/songs/s1/comments/c1'), { text: 'x' }));
    await assertFails(deleteDoc(doc(db('ewa'), 'teams/band/songs/s1/comments/c1')));
    await assertSucceeds(deleteDoc(doc(db('marek'), 'teams/band/songs/s1/comments/c1')));
  });
});

describe('Wiadomości-zdarzenia', () => {
  const event = (uid, extra) => ({
    text: 'dodaje piosenkę „Barka”', authorId: uid, authorName: uid,
    createdAt: serverTimestamp(), ...extra,
  });

  test('dozwolone typy z odnośnikami', async () => {
    await assertSucceeds(setDoc(doc(db('ewa'), 'teams/band/messages/m1'), event('ewa', { type: 'song_added', songId: 's1' })));
    await assertSucceeds(setDoc(doc(db('ewa'), 'teams/band/messages/m2'), event('ewa', { type: 'songs_imported', count: 25 })));
    await assertSucceeds(setDoc(doc(db('ewa'), 'teams/band/messages/m3'), event('ewa', { type: 'setlist', playlistId: 'p1' })));
  });

  test('nieznany typ i złe typy pól są odrzucane', async () => {
    await assertFails(setDoc(doc(db('ewa'), 'teams/band/messages/m1'), event('ewa', { type: 'admin' })));
    await assertFails(setDoc(doc(db('ewa'), 'teams/band/messages/m2'), event('ewa', { type: 'songs_imported', count: '25' })));
  });
});

describe('Obecność (kto ma otwartą aplikację)', () => {
  const presence = (online) => ({ online, lastActive: serverTimestamp() });

  test('każdy zapisuje tylko swój status', async () => {
    await assertSucceeds(setDoc(doc(db('ewa'), 'presence/ewa'), presence(true)));
    await assertFails(setDoc(doc(db('ewa'), 'presence/marek'), presence(true)));
    await assertFails(setDoc(doc(db('ewa'), 'presence/ewa'), { online: true, lastActive: Timestamp.now() }));
    await assertFails(setDoc(doc(db('ewa'), 'presence/ewa'), { ...presence(true), extra: 1 }));
  });

  test('zalogowani czytają, niezalogowani nie', async () => {
    await assertSucceeds(getDoc(doc(db('marek'), 'presence/ewa')));
    await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), 'presence/ewa')));
  });
});

describe('Zdarzenia w czasie przeszłym i wiadomości przy dołączaniu', () => {
  test('wiadomość "dołączył" zapisuje się razem z dołączeniem', async () => {
    await seedInvite('JOIN2345');
    await assertSucceeds(join('nowy', 'JOIN2345', 'band', { withMessage: true }));
  });

  test('obcy nie dopisze wiadomości bez dołączenia', async () => {
    await assertFails(setDoc(doc(db('obcy'), 'teams/band/messages/x'), {
      type: 'joined', text: 'dołączył do zespołu', authorId: 'obcy', authorName: 'Obcy',
      createdAt: serverTimestamp(),
    }));
  });

  test('forma autora i tytuł', async () => {
    const event = (extra) => ({
      type: 'song_added', text: 'dodała piosenkę „Barka”', authorId: 'ewa', authorName: 'Ewa',
      createdAt: serverTimestamp(), subject: 'Barka', ...extra,
    });
    await assertSucceeds(setDoc(doc(db('ewa'), 'teams/band/messages/a'), event({ authorForm: 'f' })));
    await assertFails(setDoc(doc(db('ewa'), 'teams/band/messages/b'), event({ authorForm: 'x' })));
    await assertFails(setDoc(doc(db('ewa'), 'teams/band/messages/c'), event({ authorForm: 'f', subject: 'x'.repeat(301) })));
  });
});

describe('Zmiana nazwy zespołu i imienia', () => {
  test('owner i editor zmieniają nazwę razem z wiadomością na czacie, member nie', async () => {
    const rename = (uid) => {
      const store = db(uid);
      const batch = writeBatch(store);
      batch.update(doc(store, 'teams/band'), { name: 'Nowa nazwa' });
      batch.set(doc(store, `teams/band/messages/r-${uid}`), {
        type: 'team_renamed', text: 'zmienił nazwę zespołu na „Nowa nazwa”', subject: 'Nowa nazwa',
        authorId: uid, authorName: uid, authorForm: 'm', createdAt: serverTimestamp(),
      });
      return batch.commit();
    };
    await assertFails(rename('marek'));
    await assertSucceeds(rename('ewa'));
    await assertSucceeds(rename('olek'));
  });

  test('każdy członek zmienia swoje imię w zespole', async () => {
    await assertSucceeds(updateDoc(doc(db('ewa'), 'teams/band'), { 'memberNames.ewa': 'Ewelina' }));
    await assertFails(updateDoc(doc(db('ewa'), 'teams/band'), { 'memberNames.ewa': '' }));
  });
});
