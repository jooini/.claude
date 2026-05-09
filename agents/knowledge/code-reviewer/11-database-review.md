# DB 관련 리뷰

> 참조 링크: https://typeorm.io/, https://mariadb.com/kb/en/transactions/, https://www.postgresql.org/docs/current/indexes.html

---

## 개요

데이터베이스 관련 코드 리뷰는 트랜잭션 안전성, 인덱스 적절성, 마이그레이션 안전성, 멱등성을 중심으로 검토한다. DB 관련 버그는 데이터 손실로 이어질 수 있어 가장 높은 주의가 필요하다.

## 1. 트랜잭션

### 트랜잭션 누락

```typescript
// ❌ 트랜잭션 없이 여러 엔티티 수정 — 중간 실패 시 정합성 깨짐
async transferPoints(fromId: string, toId: string, amount: number): Promise<void> {
  const from = await this.userRepo.findOneOrFail({ where: { id: fromId } });
  const to = await this.userRepo.findOneOrFail({ where: { id: toId } });

  from.points -= amount;
  await this.userRepo.save(from); // 여기서 성공

  to.points += amount;
  await this.userRepo.save(to); // 여기서 실패하면 from만 차감됨
}

// ✅ 트랜잭션으로 원자성 보장
async transferPoints(fromId: string, toId: string, amount: number): Promise<void> {
  await this.dataSource.transaction(async (manager) => {
    const from = await manager.findOneOrFail(User, { where: { id: fromId } });
    const to = await manager.findOneOrFail(User, { where: { id: toId } });

    from.points -= amount;
    to.points += amount;

    await manager.save([from, to]); // 전부 성공하거나 전부 롤백
  });
}
```

### 트랜잭션 범위 과다

```typescript
// ❌ 트랜잭션 안에서 외부 API 호출 — 락 시간 증가
await this.dataSource.transaction(async (manager) => {
  const order = await manager.save(Order, orderData);
  await this.paymentGateway.charge(order.total); // 외부 API (느릴 수 있음)
  await this.emailService.sendConfirmation(order); // 또 외부 호출
  order.status = 'confirmed';
  await manager.save(order);
});

// ✅ 트랜잭션은 DB 작업만, 외부 호출은 밖에서
const order = await this.dataSource.transaction(async (manager) => {
  const order = await manager.save(Order, orderData);
  order.status = 'pending_payment';
  return manager.save(order);
});

const paymentResult = await this.paymentGateway.charge(order.total);

await this.dataSource.transaction(async (manager) => {
  order.status = paymentResult.success ? 'confirmed' : 'payment_failed';
  order.paymentId = paymentResult.id;
  await manager.save(order);
});
```

### 트랜잭션 체크리스트

- [ ] 여러 테이블을 수정하는 작업에 트랜잭션이 적용되어 있는가?
- [ ] 트랜잭션 범위 안에 외부 API 호출이 포함되지 않았는가?
- [ ] 트랜잭션 격리 수준이 요구사항에 맞는가?
- [ ] 트랜잭션 내에서 반환값이 올바르게 전달되는가?
- [ ] Nested transaction 사용 시 savepoint를 인지하고 있는가?

## 2. 인덱스

### 인덱스 누락/과다

```typescript
// ❌ 자주 조회하는 컬럼에 인덱스 없음
@Entity()
class Order {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column()
  userId: string; // WHERE userId = ? 빈번한데 인덱스 없음

  @Column()
  status: string; // WHERE status = 'pending' 자주 조회

  @Column()
  createdAt: Date;
}

// ✅ 쿼리 패턴에 맞는 인덱스
@Entity()
@Index(['userId', 'status']) // 복합 인덱스: userId + status 같이 검색 빈번
@Index(['createdAt'])        // 정렬/범위 조회용
class Order {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column()
  @Index() // 단독 조회도 있을 경우
  userId: string;

  @Column()
  status: string;

  @Column()
  createdAt: Date;
}
```

### 인덱스 리뷰 가이드

```typescript
// 복합 인덱스 순서가 중요
// WHERE userId = ? AND status = ? → @Index(['userId', 'status']) ✅
// WHERE status = ? AND userId = ? → 같은 인덱스 사용 가능 (옵티마이저가 처리)
// WHERE status = ? → @Index(['userId', 'status'])로는 효율 낮음 (선두 컬럼 불일치)

// ❌ 카디널리티 낮은 컬럼만으로 인덱스
@Index(['isActive']) // true/false 2개 값 → 인덱스 효과 미미

// ✅ 카디널리티 높은 컬럼 우선
@Index(['userId', 'isActive']) // userId 카디널리티 높음 → 효과적
```

### 인덱스 체크리스트

- [ ] WHERE 절에 자주 사용되는 컬럼에 인덱스가 있는가?
- [ ] ORDER BY 컬럼에 인덱스가 있는가?
- [ ] JOIN 조건 컬럼에 인덱스가 있는가?
- [ ] 복합 인덱스 순서가 쿼리 패턴과 일치하는가?
- [ ] 불필요한 인덱스가 쓰기 성능을 저하시키지 않는가?
- [ ] UNIQUE 제약이 필요한 곳에 적용되어 있는가?

## 3. 마이그레이션 안전성

### 위험한 마이그레이션

```typescript
// ❌ 프로덕션에서 위험한 마이그레이션
class Migration1234 implements MigrationInterface {
  async up(queryRunner: QueryRunner): Promise<void> {
    // 대형 테이블 컬럼 추가 + NOT NULL + 기본값 없음 → 기존 데이터 에러
    await queryRunner.query(`ALTER TABLE users ADD COLUMN phone VARCHAR(20) NOT NULL`);

    // 인덱스 생성 시 테이블 락
    await queryRunner.query(`CREATE INDEX idx_users_email ON users(email)`);

    // 컬럼 타입 변경 — 테이블 재생성 필요 (대형 테이블에서 다운타임)
    await queryRunner.query(`ALTER TABLE orders MODIFY COLUMN status INT`);
  }
}

// ✅ 안전한 마이그레이션
class Migration1234 implements MigrationInterface {
  async up(queryRunner: QueryRunner): Promise<void> {
    // 1단계: nullable로 추가
    await queryRunner.query(`ALTER TABLE users ADD COLUMN phone VARCHAR(20) NULL`);

    // 2단계: 기본값으로 기존 데이터 채움 (별도 마이그레이션 or 배치)
    // await queryRunner.query(`UPDATE users SET phone = '' WHERE phone IS NULL`);

    // 3단계: NOT NULL 제약 추가 (데이터 채운 후)
    // await queryRunner.query(`ALTER TABLE users MODIFY COLUMN phone VARCHAR(20) NOT NULL`);
  }

  async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`ALTER TABLE users DROP COLUMN phone`);
  }
}
```

### 마이그레이션 체크리스트

- [ ] `down()` 메서드가 구현되어 있는가? (롤백 가능)
- [ ] NOT NULL 컬럼 추가 시 기본값이 있거나, nullable로 먼저 추가하는가?
- [ ] 대형 테이블 ALTER 시 다운타임 영향을 고려했는가?
- [ ] 컬럼 삭제 전 코드에서 해당 컬럼 참조가 제거되었는가?
- [ ] 마이그레이션이 재실행 가능한가? (멱등성)
- [ ] 인덱스 생성 시 `ALGORITHM=INPLACE` 또는 `CONCURRENTLY` 옵션을 검토했는가?

## 4. 멱등성

### 멱등하지 않은 작업

```typescript
// ❌ 중복 실행 시 데이터 이상
async addBonus(userId: string, amount: number): Promise<void> {
  const user = await this.userRepo.findOneOrFail({ where: { id: userId } });
  user.balance += amount; // 중복 호출 시 이중 지급
  await this.userRepo.save(user);
}

// ✅ 멱등성 키로 중복 방지
async addBonus(userId: string, amount: number, idempotencyKey: string): Promise<void> {
  const existing = await this.bonusLogRepo.findOne({ where: { idempotencyKey } });
  if (existing) return; // 이미 처리됨

  await this.dataSource.transaction(async (manager) => {
    await manager.save(BonusLog, { userId, amount, idempotencyKey });

    await manager
      .createQueryBuilder()
      .update(User)
      .set({ balance: () => `balance + ${amount}` })
      .where('id = :id', { id: userId })
      .execute();
  });
}
```

### 시드/마이그레이션 멱등성

```typescript
// ❌ 시드를 다시 실행하면 중복 데이터
async seed(): Promise<void> {
  await this.roleRepo.save({ name: 'admin', description: '관리자' });
  await this.roleRepo.save({ name: 'user', description: '일반 사용자' });
}

// ✅ UPSERT로 멱등성 보장
async seed(): Promise<void> {
  await this.roleRepo.upsert(
    [
      { name: 'admin', description: '관리자' },
      { name: 'user', description: '일반 사용자' },
    ],
    ['name'], // conflict 기준 컬럼
  );
}
```

### 멱등성 체크리스트

- [ ] 동일 요청 재전송 시 부작용 없이 같은 결과를 반환하는가?
- [ ] 결제/포인트 등 금전 관련 작업에 멱등성 키가 있는가?
- [ ] 시드/마이그레이션이 재실행 가능한가?
- [ ] 메시지 큐 컨슈머가 중복 메시지를 안전하게 처리하는가?

## 리뷰어 종합 체크리스트

| 항목 | 확인 내용 | 심각도 |
|------|----------|--------|
| 트랜잭션 누락 | 다중 테이블 변경에 트랜잭션 없음 | P0 |
| 멱등성 부재 | 금전 작업 중복 실행 가능 | P0 |
| 마이그레이션 위험 | NOT NULL 추가, 대형 테이블 ALTER | P0 |
| 인덱스 누락 | 빈번 조회 컬럼에 인덱스 없음 | P1 |
| 트랜잭션 과대 | 외부 호출 포함 | P1 |
| 롤백 미구현 | down() 없는 마이그레이션 | P2 |
| 인덱스 과다 | 쓰기 성능 저하 | P2 |
